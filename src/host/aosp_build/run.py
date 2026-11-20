"""run-aosp.sh: run the non-RPi outputs of build-aosp.sh on the host.

The outputs are in <outdir>/<subdir> (build-info.json, and images/ and
cvd-host_package.tar.gz for cuttlefish, or sdk-repo-linux-system-images.zip
for the emulator). The state of a running device is kept in
<outdir>/<subdir>/run-<target>/, separately from the outputs.
See docs-ai/task/form-factor-and-run-targets/03-run-script.md.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import zipfile
from typing import Dict, List, Optional

TARGETS_BY_PLATFORM = {
    "cuttlefish": ("cf-host",),
    "emulator": ("emulator",),
}

CF_GPU_MODES = ("auto", "drm_virgl", "gfxstream", "gfxstream_guest_angle",
                "gfxstream_guest_angle_host_swiftshader", "guest_swiftshader",
                "none")
# The modes that use the GPU of the host (a render node is required).
CF_HOST_GPU_MODES = ("drm_virgl", "gfxstream", "gfxstream_guest_angle")
CF_DEFAULT_GPU_MODE = "gfxstream"
EMULATOR_DEFAULT_GPU_MODE = "host"

ADB_PORT = 6520
TAP_DEVICE = "cvd-mtap-01"

# The API level of the system image by the android version. 16 (bp4a) is
# SDK 36.1 (RELEASE_PLATFORM_SDK_VERSION_FULL); the target uses the major 36.
API_LEVELS = {"14": 34, "16": 36}

AVD_TAGS = {
    "phone": ("default", "Default"),
    "tv": ("android-tv", "Android TV"),
    "auto": ("android-automotive", "Android Automotive"),
}
# (width, height, density)
AVD_LCD = {"phone": (1080, 2400, 420), "tv": (1920, 1080, 213),
           "auto": (1920, 1080, 213)}


EMULATOR_STOP_ERROR = ("error: --stop is not supported for the emulator. "
                       "Close the window of the emulator.")


class Exit(Exception):
    def __init__(self, code: int, message: Optional[str] = None):
        super().__init__(message)
        self.code = code
        self.message = message


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="run-aosp.sh", allow_abbrev=False,
        usage="%(prog)s [OPTION...] [-- <launcher options>]",
        description="Run the outputs of build-aosp.sh (cuttlefish or the "
                    "Android Emulator) on the host. The options after '--' "
                    "are passed to launch_cvd or emulator as they are.")
    parser.add_argument("--outdir", metavar="DIR",
                        help="The directory that output binaries (same as "
                             "build-aosp.sh). (required)")
    parser.add_argument("-t", dest="subdir", metavar="NAME",
                        help="Output subdirectory name, e.g. "
                             "android-14-x86_64-auto. (required)")
    parser.add_argument("--target", choices=("cf-host", "emulator"),
                        help="Where to run. The default depends on the "
                             "platform of the build (cuttlefish: cf-host, "
                             "emulator: emulator).")
    parser.add_argument("--gpu-mode", metavar="MODE",
                        help="cf-host: %s (default), %s. emulator: %s "
                             "(default), swiftshader_indirect, ..."
                             % (CF_DEFAULT_GPU_MODE,
                                ", ".join(m for m in CF_GPU_MODES
                                          if m != CF_DEFAULT_GPU_MODE),
                                EMULATOR_DEFAULT_GPU_MODE))
    parser.add_argument("--wipe", action="store_true",
                        help="Discard the previous state (userdata) before "
                             "starting.")
    parser.add_argument("--stop", action="store_true",
                        help="Stop the running device (cf-host).")
    parser.add_argument("--emulator", metavar="PATH",
                        help="The emulator binary (emulator). The default is "
                             "found in $ANDROID_HOME, $ANDROID_SDK_ROOT, "
                             "~/Android/Sdk and PATH in this order.")
    parser.add_argument("--allow-remote", action="store_true",
                        help="cf-host: required to start. adb (root without "
                             "authentication on eng builds) listens on all "
                             "interfaces.")
    return parser


def split_argv(argv: List[str]) -> tuple:
    """Split the options of this script and the launcher at the first '--'."""
    if "--" in argv:
        i = argv.index("--")
        return argv[:i], argv[i + 1:]
    return argv, []


def devdir() -> str:
    # Only for tests: the device files are looked up under this directory.
    return os.environ.get("RUN_AOSP_DEVDIR", "/dev")


def check_targetdir(outdir: Optional[str], subdir: Optional[str]) -> tuple:
    """The same rules as make-image.sh. Return (targetdir, subdir)."""
    if not outdir:
        raise Exit(2, "--outdir is required.")
    if not subdir:
        raise Exit(2, "-t is required.")
    if not os.path.isdir(outdir):
        raise Exit(2, "The outdir '%s' does not exist." % outdir)
    name = subdir.rstrip("/")
    if "/" in name or name in (".", "..", ""):
        raise Exit(2, "-t must be a directory name under --outdir: %s"
                   % subdir)
    targetdir = os.path.join(os.path.realpath(outdir), name)
    if not os.path.isdir(targetdir):
        raise Exit(2, "The output '%s' does not exist." % targetdir)
    return targetdir, name


def read_build_info(targetdir: str) -> dict:
    path = os.path.join(targetdir, "build-info.json")
    if not os.path.isfile(path):
        raise Exit(1, "error: %s not found. The build has not completed, or "
                   "it was built before the outputs were copied for "
                   "cuttlefish and emulator." % path)
    try:
        with open(path) as f:
            info = json.load(f)
    except (OSError, ValueError) as e:
        raise Exit(1, "error: Failed to read %s: %s" % (path, e))
    if not isinstance(info, dict) or info.get("schema") != 1:
        raise Exit(1, "error: Unsupported %s" % path)
    for key in ("android_version", "platform", "form_factor"):
        if not isinstance(info.get(key), str):
            raise Exit(1, "error: %s: %s is missing" % (path, key))
    return info


def decide_target(platform: str, target: Optional[str]) -> str:
    if platform == "rpi4":
        raise Exit(2, "error: The output is for Raspberry Pi. Use "
                   "make-image.sh to make an SD card image.")
    targets = TARGETS_BY_PLATFORM.get(platform)
    if targets is None:
        raise Exit(1, "error: Unknown platform in build-info.json: %s"
                   % platform)
    if target is None:
        return targets[0]
    if target not in targets:
        raise Exit(2, "error: The output of %s can not run on --target %s "
                   "(available: %s)." % (platform, target, ", ".join(targets)))
    return target


def check_artifacts(targetdir: str, platform: str) -> None:
    if platform == "cuttlefish":
        required = ["images/android-info.txt", "cvd-host_package.tar.gz"]
    else:
        required = ["sdk-repo-linux-system-images.zip"]
    for name in required:
        if not os.path.isfile(os.path.join(targetdir, name)):
            raise Exit(1, "error: %s not found in %s." % (name, targetdir))


def is_newer(path: str, stamp: str) -> bool:
    """True if stamp does not exist or path is newer than stamp."""
    return (not os.path.exists(stamp)
            or os.path.getmtime(path) > os.path.getmtime(stamp))


def touch(path: str) -> None:
    with open(path, "w"):
        pass


def warn(message: str) -> None:
    print("warning: %s" % message, file=sys.stderr)


def run_quiet(argv: List[str]) -> Optional[subprocess.CompletedProcess]:
    """Run a command for a check. None if the command is not found."""
    try:
        return subprocess.run(argv, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL,
                              universal_newlines=True)
    except OSError:
        return None


# ---------------------------------------------------------------------------
# cf-host

def check_device(name: str, hint: str) -> None:
    path = os.path.join(devdir(), name)
    if not os.path.exists(path):
        raise Exit(1, "error: %s not found. %s" % (path, hint))
    if not os.access(path, os.R_OK | os.W_OK):
        raise Exit(1, "error: No permission to read and write %s. %s"
                   % (path, hint))


def check_render_node(gpu_mode: str) -> None:
    nodes = glob.glob(os.path.join(devdir(), "dri", "renderD*"))
    if not any(os.access(n, os.R_OK | os.W_OK) for n in nodes):
        raise Exit(1, "error: --gpu-mode %s needs a render node "
                   "(%s/dri/renderD*) readable and writable. Add the user to "
                   "the 'render' group, or use --gpu-mode guest_swiftshader."
                   % (gpu_mode, devdir()))


def check_port_free(port: int) -> None:
    r = run_quiet(["ss", "-Hltn", "sport = :%d" % port])
    if r is None or r.returncode != 0:
        warn("Failed to check the port %d by ss." % port)
        return
    if r.stdout.strip():
        raise Exit(1, "error: The port %d is in use. Another cuttlefish "
                   "device may be running (run-aosp.sh --stop, or stop_cvd)."
                   % port)


def check_tap() -> None:
    r = run_quiet(["ip", "link", "show", TAP_DEVICE])
    if r is None or r.returncode != 0:
        warn("%s not found. Install cuttlefish-base to enable the network of "
             "the device. It runs without the network (adb works)."
             % TAP_DEVICE)


def extract_host_package(targetdir: str, rundir: str) -> str:
    """Extract cvd-host_package.tar.gz to <rundir>/host if it is updated."""
    tarball = os.path.join(targetdir, "cvd-host_package.tar.gz")
    hostdir = os.path.join(rundir, "host")
    stamp = os.path.join(hostdir, ".stamp")
    if is_newer(tarball, stamp):
        print("Extracting %s" % tarball)
        shutil.rmtree(hostdir, ignore_errors=True)
        os.makedirs(hostdir)
        r = subprocess.run(["tar", "-xzf", tarball, "-C", hostdir])
        if r.returncode != 0:
            raise Exit(1, "error: Failed to extract %s" % tarball)
        touch(stamp)
    return hostdir


def cf_env(rundir: str) -> Dict[str, str]:
    # HOME: launch_cvd creates cuttlefish_runtime etc. in HOME (as the
    # official "HOME=$PWD ./bin/launch_cvd"). Do not use the user's home.
    env = dict(os.environ)
    env["HOME"] = rundir
    env["ANDROID_HOST_OUT"] = os.path.join(rundir, "host")
    return env


def stop(args, targetdir: str) -> int:
    """--stop. It does not need build-info.json nor the outputs, which a
    running build may have removed (src/container/build.sh)."""
    if args.target == "emulator":
        raise Exit(2, EMULATOR_STOP_ERROR)
    rundir = os.path.join(targetdir, "run-cf-host")
    stop_cvd = os.path.join(rundir, "host", "bin", "stop_cvd")
    if os.path.isfile(stop_cvd):
        return subprocess.run([stop_cvd], env=cf_env(rundir)).returncode
    info = None
    try:
        info = read_build_info(targetdir)
    except Exit:
        pass
    if info is not None and info["platform"] == "emulator":
        raise Exit(2, EMULATOR_STOP_ERROR)
    raise Exit(1, "error: %s not found. The device has not been started."
               % stop_cvd)


def run_cf_host(args, targetdir: str, extra: List[str]) -> int:
    rundir = os.path.join(targetdir, "run-cf-host")
    gpu_mode = args.gpu_mode or CF_DEFAULT_GPU_MODE
    if gpu_mode not in CF_GPU_MODES:
        raise Exit(2, "error: Unknown --gpu-mode for cf-host: %s (available: "
                   "%s)" % (gpu_mode, ", ".join(CF_GPU_MODES)))
    if not args.allow_remote:
        raise Exit(2, "error: cf-host exposes adb on all interfaces (port %d)."
                   " On eng builds it is a root shell without "
                   "authentication. Use it only on a trusted network or "
                   "block the ports (6520, 8443 and 15550-15599) by a "
                   "firewall, and add --allow-remote to start." % ADB_PORT)

    check_device("kvm", "Add the user to the 'kvm' group.")
    check_device("vhost-vsock", "Load the vhost_vsock module, or install "
                 "cuttlefish-base.")
    if gpu_mode in CF_HOST_GPU_MODES:
        check_render_node(gpu_mode)
    check_port_free(ADB_PORT)
    check_tap()

    os.makedirs(rundir, exist_ok=True)
    hostdir = extract_host_package(targetdir, rundir)
    launch_cvd = os.path.join(hostdir, "bin", "launch_cvd")
    argv = [launch_cvd, "--daemon",
            "--system_image_dir=%s" % os.path.join(targetdir, "images"),
            "--gpu_mode=%s" % gpu_mode,
            "--report_anonymous_usage_stats=n"]
    if args.wipe:
        argv.append("--resume=false")
    argv += extra
    print("warning: adb listens on all interfaces (port %d). It is a root "
          "shell without authentication on eng builds." % ADB_PORT,
          file=sys.stderr)
    sys.stdout.flush()
    rc = subprocess.run(argv, env=cf_env(rundir)).returncode
    if rc == 0:
        print("WebRTC: https://localhost:8443")
        print("adb:    adb connect 127.0.0.1:%d" % ADB_PORT)
        print("Stop:   run-aosp.sh --outdir %s -t %s --stop"
              % (os.path.dirname(targetdir), os.path.basename(targetdir)))
        print("The runtime files and logs are in %s" % rundir)
    return rc


# ---------------------------------------------------------------------------
# emulator

def find_emulator(option: Optional[str]) -> tuple:
    """Return (emulator, sdk root or None)."""
    if option:
        if not os.access(option, os.X_OK) or os.path.isdir(option):
            raise Exit(1, "error: %s is not an executable." % option)
        return option, None
    home = os.path.expanduser("~")
    for root in (os.environ.get("ANDROID_HOME", ""),
                 os.environ.get("ANDROID_SDK_ROOT", ""),
                 os.path.join(home, "Android", "Sdk")):
        if not root:
            continue
        path = os.path.join(root, "emulator", "emulator")
        if os.access(path, os.X_OK) and not os.path.isdir(path):
            return path, root
    path = shutil.which("emulator")
    if path:
        return path, None
    raise Exit(1, "error: The Android Emulator is not found. Install it by "
               "the SDK Manager of Android Studio or 'sdkmanager emulator', "
               "or give --emulator.")


def derive_sdk_root(emulator: str, rundir: str) -> str:
    """The SDK root for an emulator given by --emulator or found in PATH."""
    real = os.path.realpath(emulator)
    root = os.path.dirname(os.path.dirname(real))
    if os.path.isdir(os.path.join(root, "emulator")) and (
            os.path.isdir(os.path.join(root, "platform-tools"))
            or os.path.isdir(os.path.join(root, "system-images"))):
        return root
    # The system image is given by an absolute path (image.sysdir.1), so an
    # empty SDK root is expected to work.
    sdk = os.path.join(rundir, "sdk")
    os.makedirs(sdk, exist_ok=True)
    return sdk


def extract_system_image(targetdir: str, rundir: str, avd_home: str) -> str:
    """Extract the zip to <rundir>/sysimg if it is updated. Return the ABI."""
    zip_path = os.path.join(targetdir, "sdk-repo-linux-system-images.zip")
    sysimg = os.path.join(rundir, "sysimg")
    stamp = os.path.join(sysimg, ".stamp")
    if is_newer(zip_path, stamp):
        print("Extracting %s" % zip_path)
        shutil.rmtree(sysimg, ignore_errors=True)
        os.makedirs(sysimg)
        try:
            with zipfile.ZipFile(zip_path) as z:
                z.extractall(sysimg)
        except (OSError, zipfile.BadZipFile) as e:
            raise Exit(1, "error: Failed to extract %s: %s" % (zip_path, e))
        # The emulator does not discard the userdata of the AVD when the
        # system is updated. Recreate the AVD not to mix them.
        shutil.rmtree(avd_home, ignore_errors=True)
        touch(stamp)
    abis = sorted(d for d in os.listdir(sysimg)
                  if os.path.isdir(os.path.join(sysimg, d)))
    if len(abis) != 1:
        raise Exit(1, "error: Expected one ABI directory in %s, found %s"
                   % (sysimg, abis))
    return abis[0]


def avd_config(sysdir: str, abi: str, form_factor: str,
               gpu_mode: str) -> str:
    tag_id, tag_display = AVD_TAGS[form_factor]
    width, height, density = AVD_LCD[form_factor]
    values = [
        ("avd.ini.encoding", "UTF-8"),
        ("PlayStore.enabled", "no"),
        ("abi.type", abi),
        ("hw.cpu.arch", abi),
        ("image.sysdir.1", sysdir.rstrip("/") + "/"),
        ("tag.id", tag_id),
        ("tag.display", tag_display),
        ("hw.lcd.width", width),
        ("hw.lcd.height", height),
        ("hw.lcd.density", density),
        ("hw.ramSize", 4096),
        ("hw.gpu.enabled", "yes"),
        ("hw.gpu.mode", gpu_mode),
        ("hw.keyboard", "yes"),
        ("hw.dPad", "yes" if form_factor == "tv" else "no"),
    ]
    return "".join("%s=%s\n" % kv for kv in values)


def write_avd(avd_home: str, name: str, config: str, api: int) -> None:
    avd_dir = os.path.join(avd_home, name + ".avd")
    os.makedirs(avd_dir, exist_ok=True)
    with open(os.path.join(avd_home, name + ".ini"), "w") as f:
        f.write("avd.ini.encoding=UTF-8\npath=%s\ntarget=android-%d\n"
                % (avd_dir, api))
    # Rewritten every time (e.g. --gpu-mode). The userdata in avd_dir is kept.
    with open(os.path.join(avd_dir, "config.ini"), "w") as f:
        f.write(config)


def run_emulator(args, targetdir: str, name: str, info: dict,
                 extra: List[str]) -> int:
    api = API_LEVELS.get(info["android_version"])
    if api is None:
        raise Exit(1, "error: Unsupported android version for the emulator: "
                   "%s" % info["android_version"])
    if info["form_factor"] not in AVD_TAGS:
        raise Exit(1, "error: Unknown form factor in build-info.json: %s"
                   % info["form_factor"])
    emulator, sdk_root = find_emulator(args.emulator)
    rundir = os.path.join(targetdir, "run-emulator")
    os.makedirs(rundir, exist_ok=True)
    if sdk_root is None:
        sdk_root = derive_sdk_root(emulator, rundir)
    avd_home = os.path.join(rundir, "avd")
    abi = extract_system_image(targetdir, rundir, avd_home)
    gpu_mode = args.gpu_mode or EMULATOR_DEFAULT_GPU_MODE
    # The AVD name allows [a-zA-Z0-9._-].
    avd_name = re.sub(r"[^a-zA-Z0-9._-]", "_", name)
    write_avd(avd_home, avd_name,
              avd_config(os.path.join(rundir, "sysimg", abi), abi,
                         info["form_factor"], gpu_mode), api)

    env = dict(os.environ)
    # ANDROID_HOME of the user may point to another SDK.
    env["ANDROID_HOME"] = sdk_root
    env["ANDROID_SDK_ROOT"] = sdk_root
    env["ANDROID_AVD_HOME"] = avd_home
    # -no-snapshot: do not boot from a snapshot of an older build.
    argv = [emulator, "-avd", avd_name, "-gpu", gpu_mode, "-no-snapshot"]
    if args.wipe:
        argv.append("-wipe-data")
    argv += extra
    sys.stdout.flush()
    sys.stderr.flush()
    try:
        os.execve(emulator, argv, env)
    except OSError as e:
        raise Exit(127, "error: Failed to run %s: %s" % (emulator, e))
    return 127  # not reached


def run(argv: List[str]) -> int:
    own, extra = split_argv(argv)
    args = build_parser().parse_args(own)
    if args.stop and args.wipe:
        raise Exit(2, "error: --wipe can not be used with --stop.")
    targetdir, name = check_targetdir(args.outdir, args.subdir)
    if args.stop:
        return stop(args, targetdir)
    info = read_build_info(targetdir)
    target = decide_target(info["platform"], args.target)
    check_artifacts(targetdir, info["platform"])
    if target == "cf-host":
        return run_cf_host(args, targetdir, extra)
    return run_emulator(args, targetdir, name, info, extra)


def main(argv: Optional[List[str]] = None) -> int:
    try:
        return run(sys.argv[1:] if argv is None else argv)
    except Exit as e:
        if e.message:
            print(e.message, file=sys.stderr)
        return e.code
