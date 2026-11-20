"""Tests for run-aosp.sh with stub commands.

launch_cvd and stop_cvd are in a fake cvd-host_package.tar.gz. ss, ip and
emulator are stubs in PATH. The device files are in RUN_AOSP_DEVDIR.
"""
from __future__ import annotations

import json
import os
import shutil
import stat
import subprocess
import tarfile
import tempfile
import textwrap
import time
import unittest
import zipfile

from helpers import REPODIR

# Records the argv and some environment variables as a JSON line.
RECORDER = textwrap.dedent('''\
    #!/usr/bin/env python3
    import json, os, sys
    with open(os.environ["STUB_LOG"], "a") as f:
        f.write(json.dumps({
            "name": os.path.basename(sys.argv[0]),
            "argv": sys.argv[1:],
            "HOME": os.environ.get("HOME"),
            "ANDROID_HOST_OUT": os.environ.get("ANDROID_HOST_OUT"),
            "ANDROID_HOME": os.environ.get("ANDROID_HOME"),
            "ANDROID_SDK_ROOT": os.environ.get("ANDROID_SDK_ROOT"),
            "ANDROID_AVD_HOME": os.environ.get("ANDROID_AVD_HOME"),
        }) + "\\n")
    ''')

SS = textwrap.dedent('''\
    #!/bin/sh
    if [ "$STUB_SS_BUSY" = 1 ]; then
      echo "LISTEN 0 4096 0.0.0.0:6520 0.0.0.0:*"
    fi
    ''')

IP = '#!/bin/sh\nexit ${STUB_IP_RC:-0}\n'


def write_exec(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)
    os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


class RunTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.stub = os.path.join(self.dir, "stub")
        write_exec(os.path.join(self.stub, "ss"), SS)
        write_exec(os.path.join(self.stub, "ip"), IP)
        self.dev = os.path.join(self.dir, "dev")
        for name in ("kvm", "vhost-vsock", "dri/renderD128"):
            path = os.path.join(self.dev, name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "w").close()
        self.out = os.path.join(self.dir, "out")
        os.mkdir(self.out)
        self.log = os.path.join(self.dir, "stub.log")
        self.home = os.path.join(self.dir, "home")
        os.mkdir(self.home)
        self.env = dict(os.environ, STUB_LOG=self.log,
                        RUN_AOSP_DEVDIR=self.dev, HOME=self.home,
                        PATH=self.stub + ":/usr/bin:/bin",
                        PYTHONDONTWRITEBYTECODE="1")
        for key in ("ANDROID_HOME", "ANDROID_SDK_ROOT", "STUB_SS_BUSY",
                    "STUB_IP_RC"):
            self.env.pop(key, None)

    def tearDown(self):
        self.tmp.cleanup()

    def make_output(self, name, info, artifacts=True):
        d = os.path.join(self.out, name)
        os.makedirs(d)
        if info is not None:
            data = dict(schema=1, android_version="14", arch="x86_64",
                        lunch_choice="x", aosp_branch="y")
            data.update(info)
            with open(os.path.join(d, "build-info.json"), "w") as f:
                json.dump(data, f)
        if artifacts and info and info.get("platform") == "cuttlefish":
            os.makedirs(os.path.join(d, "images"))
            open(os.path.join(d, "images", "android-info.txt"), "w").close()
            self.make_host_package(d)
        if artifacts and info and info.get("platform") == "emulator":
            self.make_zip(d, "x86" if info.get("form_factor") == "tv"
                          else "x86_64")
        return d

    def make_host_package(self, d):
        src = os.path.join(self.dir, "pkg")
        for name in ("launch_cvd", "stop_cvd"):
            write_exec(os.path.join(src, "bin", name), RECORDER)
        with tarfile.open(os.path.join(d, "cvd-host_package.tar.gz"),
                          "w:gz") as t:
            t.add(os.path.join(src, "bin"), arcname="bin")

    def make_zip(self, d, abi):
        with zipfile.ZipFile(os.path.join(
                d, "sdk-repo-linux-system-images.zip"), "w") as z:
            z.writestr(abi + "/system.img", "system")
            z.writestr(abi + "/source.properties", "x")

    def run_aosp(self, *args, env=None):
        e = dict(self.env)
        e.update(env or {})
        r = subprocess.run(["bash", os.path.join(REPODIR, "run-aosp.sh")]
                           + list(args), env=e, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, universal_newlines=True)
        self.stdout, self.stderr = r.stdout, r.stderr
        return r.returncode

    def calls(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log) as f:
            return [json.loads(line) for line in f]


class TestCommon(RunTestCase):
    def test_help(self):
        self.assertEqual(self.run_aosp("-h"), 0)
        self.assertIn("--allow-remote", self.stdout)

    def test_unknown_target(self):
        self.make_output("a", {"platform": "cuttlefish", "form_factor": "tv"})
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t", "a",
                                       "--target", "cf-docker"), 2)

    def test_required(self):
        self.assertEqual(self.run_aosp("-t", "a"), 2)
        self.assertIn("--outdir is required", self.stderr)
        self.assertEqual(self.run_aosp("--outdir", self.out), 2)
        self.assertIn("-t is required", self.stderr)

    def test_subdir(self):
        for name in ("a/b", "..", "."):
            self.assertEqual(self.run_aosp("--outdir", self.out, "-t", name),
                             2, name)
            self.assertIn("-t must be a directory name", self.stderr)
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t", "none"), 2)
        self.assertIn("does not exist", self.stderr)

    def test_no_build_info(self):
        self.make_output("a", None)
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t", "a"), 1)
        self.assertIn("build-info.json not found", self.stderr)

    def test_missing_artifacts(self):
        self.make_output("a", {"platform": "cuttlefish", "form_factor": "tv"},
                         artifacts=False)
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t", "a",
                                       "--allow-remote"), 1)
        self.assertIn("images/android-info.txt not found", self.stderr)
        self.make_output("b", {"platform": "emulator", "form_factor": "tv"},
                         artifacts=False)
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t", "b"), 1)
        self.assertIn("sdk-repo-linux-system-images.zip not found",
                      self.stderr)

    def test_platform_and_target(self):
        self.make_output("a", {"platform": "emulator", "form_factor": "tv"})
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t", "a",
                                       "--target", "cf-host"), 2)
        self.assertIn("can not run on --target cf-host", self.stderr)
        self.assertEqual(self.calls(), [])

    def test_rpi(self):
        self.make_output("a", {"platform": "rpi4", "form_factor": "tv"})
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t", "a"), 2)
        self.assertIn("make-image.sh", self.stderr)

    def test_stop_and_wipe(self):
        self.make_output("a", {"platform": "cuttlefish", "form_factor": "tv"})
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t", "a",
                                       "--stop", "--wipe"), 2)


class TestCfHost(RunTestCase):
    def setUp(self):
        super().setUp()
        self.target = self.make_output(
            "android-14-x86_64-auto",
            {"platform": "cuttlefish", "form_factor": "auto"})
        self.rundir = os.path.join(self.target, "run-cf-host")

    def start(self, *args, env=None):
        return self.run_aosp("--outdir", self.out, "-t",
                             "android-14-x86_64-auto", "--allow-remote",
                             *args, env=env)

    def launch(self):
        calls = [c for c in self.calls() if c["name"] == "launch_cvd"]
        self.assertEqual(len(calls), 1, self.calls())
        return calls[0]

    def test_launch(self):
        self.assertEqual(self.start(), 0, self.stderr)
        c = self.launch()
        self.assertEqual(c["argv"], [
            "--daemon",
            "--system_image_dir=%s/images" % os.path.realpath(self.target),
            "--gpu_mode=gfxstream", "--report_anonymous_usage_stats=n"])
        self.assertEqual(c["HOME"], os.path.realpath(self.rundir))
        self.assertEqual(c["ANDROID_HOST_OUT"],
                         os.path.realpath(self.rundir) + "/host")
        self.assertIn("adb listens on all interfaces", self.stderr)
        self.assertIn("https://localhost:8443", self.stdout)

    def test_target_is_explicit(self):
        self.assertEqual(self.start("--target", "cf-host"), 0, self.stderr)
        self.launch()

    def test_allow_remote_is_required(self):
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t",
                                       "android-14-x86_64-auto"), 2)
        self.assertIn("--allow-remote", self.stderr)
        self.assertEqual(self.calls(), [])
        self.assertFalse(os.path.exists(self.rundir))

    def test_gpu_mode_and_extra_args(self):
        self.assertEqual(self.start("--gpu-mode", "drm_virgl", "--",
                                    "--cpus=4", "--memory_mb=8192"),
                         0, self.stderr)
        argv = self.launch()["argv"]
        self.assertIn("--gpu_mode=drm_virgl", argv)
        self.assertEqual(argv[-2:], ["--cpus=4", "--memory_mb=8192"])

    def test_unknown_gpu_mode(self):
        self.assertEqual(self.start("--gpu-mode", "host"), 2)
        self.assertEqual(self.calls(), [])

    def test_wipe(self):
        self.assertEqual(self.start(), 0, self.stderr)
        self.assertNotIn("--resume=false", self.launch()["argv"])
        os.unlink(self.log)
        self.assertEqual(self.start("--wipe"), 0, self.stderr)
        self.assertIn("--resume=false", self.launch()["argv"])

    def test_host_package_is_extracted_once(self):
        self.assertEqual(self.start(), 0, self.stderr)
        marker = os.path.join(self.rundir, "host", "marker")
        open(marker, "w").close()
        self.assertEqual(self.start(), 0, self.stderr)
        self.assertTrue(os.path.exists(marker))
        # A newer tarball is extracted again.
        tarball = os.path.join(self.target, "cvd-host_package.tar.gz")
        future = time.time() + 10
        os.utime(tarball, (future, future))
        self.assertEqual(self.start(), 0, self.stderr)
        self.assertFalse(os.path.exists(marker))

    def test_port_in_use(self):
        self.assertEqual(self.start(env={"STUB_SS_BUSY": "1"}), 1)
        self.assertIn("6520 is in use", self.stderr)
        self.assertEqual(self.calls(), [])

    def test_no_tap(self):
        self.assertEqual(self.start(env={"STUB_IP_RC": "1"}), 0, self.stderr)
        self.assertIn("cvd-mtap-01 not found", self.stderr)
        self.launch()

    @unittest.skipIf(os.getuid() == 0, "root can access any file")
    def test_no_permission_of_kvm(self):
        os.chmod(os.path.join(self.dev, "kvm"), 0)
        self.assertEqual(self.start(), 1)
        self.assertIn("kvm", self.stderr)
        self.assertEqual(self.calls(), [])

    def test_no_vhost_vsock(self):
        os.unlink(os.path.join(self.dev, "vhost-vsock"))
        self.assertEqual(self.start(), 1)
        self.assertIn("vhost-vsock not found", self.stderr)

    def test_render_node(self):
        os.unlink(os.path.join(self.dev, "dri", "renderD128"))
        self.assertEqual(self.start(), 1)
        self.assertIn("render node", self.stderr)
        self.assertEqual(self.start("--gpu-mode", "guest_swiftshader"), 0,
                         self.stderr)

    def test_stop(self):
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t",
                                       "android-14-x86_64-auto", "--stop"), 1)
        self.assertIn("has not been started", self.stderr)
        self.assertEqual(self.start(), 0, self.stderr)
        os.unlink(self.log)
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t",
                                       "android-14-x86_64-auto", "--stop"),
                         0, self.stderr)
        [c] = self.calls()
        self.assertEqual(c["name"], "stop_cvd")
        self.assertEqual(c["HOME"], os.path.realpath(self.rundir))

    def test_stop_while_rebuilding(self):
        # build.sh removes build-info.json and images/ before copying.
        self.assertEqual(self.start(), 0, self.stderr)
        os.unlink(self.log)
        os.unlink(os.path.join(self.target, "build-info.json"))
        shutil.rmtree(os.path.join(self.target, "images"))
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t",
                                       "android-14-x86_64-auto", "--stop"),
                         0, self.stderr)
        [c] = self.calls()
        self.assertEqual(c["name"], "stop_cvd")


class TestEmulator(RunTestCase):
    def setUp(self):
        super().setUp()
        self.name = "android-14-x86_64-emulator-tv"
        self.target = self.make_output(
            self.name, {"platform": "emulator", "form_factor": "tv"})
        self.rundir = os.path.realpath(os.path.join(self.target,
                                                    "run-emulator"))

    def make_sdk(self, root, extra_dirs=("platform-tools",)):
        write_exec(os.path.join(root, "emulator", "emulator"), RECORDER)
        for d in extra_dirs:
            os.makedirs(os.path.join(root, d), exist_ok=True)
        return os.path.join(root, "emulator", "emulator")

    def start(self, *args, env=None):
        return self.run_aosp("--outdir", self.out, "-t", self.name, *args,
                             env=env)

    def emulator(self):
        calls = [c for c in self.calls() if c["name"] == "emulator"]
        self.assertEqual(len(calls), 1, self.calls())
        return calls[0]

    def config(self):
        path = os.path.join(self.rundir, "avd", self.name + ".avd",
                            "config.ini")
        with open(path) as f:
            return dict(line.rstrip("\n").split("=", 1) for line in f)

    def test_run(self):
        sdk = os.path.join(self.dir, "sdk")
        self.make_sdk(sdk)
        self.assertEqual(self.start(env={"ANDROID_HOME": sdk}), 0, self.stderr)
        c = self.emulator()
        self.assertEqual(c["argv"], ["-avd", self.name, "-gpu", "host",
                                     "-no-snapshot"])
        self.assertEqual(c["ANDROID_SDK_ROOT"], sdk)
        self.assertEqual(c["ANDROID_HOME"], sdk)
        self.assertEqual(c["ANDROID_AVD_HOME"], self.rundir + "/avd")
        config = self.config()
        self.assertEqual(config["image.sysdir.1"],
                         self.rundir + "/sysimg/x86/")
        self.assertEqual(config["abi.type"], "x86")
        self.assertEqual(config["tag.id"], "android-tv")
        self.assertEqual(config["hw.dPad"], "yes")
        self.assertEqual(config["hw.gpu.mode"], "host")
        with open(os.path.join(self.rundir, "avd", self.name + ".ini")) as f:
            self.assertIn("target=android-34\n", f.read())

    def test_android_16(self):
        """16 (bp4a, SDK 36.1) is API level 36."""
        sdk = os.path.join(self.dir, "sdk")
        self.make_sdk(sdk)
        name = "android-16-x86_64-emulator-tv"
        self.make_output(name, {"android_version": "16",
                                "platform": "emulator", "form_factor": "tv"})
        self.assertEqual(self.run_aosp("--outdir", self.out, "-t", name,
                                       env={"ANDROID_HOME": sdk}),
                         0, self.stderr)
        avd = os.path.join(self.out, name, "run-emulator", "avd", name + ".ini")
        with open(avd) as f:
            self.assertIn("target=android-36\n", f.read())

    def test_wipe_gpu_and_extra_args(self):
        sdk = os.path.join(self.dir, "sdk")
        self.make_sdk(sdk)
        self.assertEqual(self.start("--wipe", "--gpu-mode",
                                    "swiftshader_indirect", "--", "-verbose",
                                    env={"ANDROID_HOME": sdk}),
                         0, self.stderr)
        self.assertEqual(self.emulator()["argv"][3:],
                         ["swiftshader_indirect", "-no-snapshot",
                          "-wipe-data", "-verbose"])
        self.assertEqual(self.config()["hw.gpu.mode"],
                         "swiftshader_indirect")

    def test_resolution_order(self):
        home_sdk = os.path.join(self.home, "Android", "Sdk")
        sdk_root = os.path.join(self.dir, "sdk_root")
        android_home = os.path.join(self.dir, "android_home")
        for root in (home_sdk, sdk_root, android_home):
            self.make_sdk(root)
        write_exec(os.path.join(self.stub, "emulator"), RECORDER)
        cases = [
            ({"ANDROID_HOME": android_home, "ANDROID_SDK_ROOT": sdk_root},
             android_home),
            ({"ANDROID_SDK_ROOT": sdk_root}, sdk_root),
            ({}, home_sdk),
        ]
        for env, expected in cases:
            with self.subTest(env=env):
                if os.path.exists(self.log):
                    os.unlink(self.log)
                self.assertEqual(self.start(env=env), 0, self.stderr)
                self.assertEqual(self.emulator()["ANDROID_SDK_ROOT"],
                                 expected)
        # PATH
        os.unlink(os.path.join(home_sdk, "emulator", "emulator"))
        os.unlink(self.log)
        self.assertEqual(self.start(), 0, self.stderr)
        self.assertEqual(self.emulator()["ANDROID_SDK_ROOT"],
                         self.rundir + "/sdk")

    def test_emulator_option(self):
        sdk = os.path.join(self.dir, "sdk")
        emulator = self.make_sdk(sdk)
        other = os.path.join(self.dir, "prebuilts", "emulator")
        write_exec(other, RECORDER)
        # --emulator is used even if ANDROID_HOME is set.
        self.assertEqual(self.start("--emulator", other,
                                    env={"ANDROID_HOME": sdk}), 0, self.stderr)
        # It is not in an SDK.
        self.assertEqual(self.emulator()["ANDROID_SDK_ROOT"],
                         self.rundir + "/sdk")
        # In an SDK, the SDK root is derived.
        os.unlink(self.log)
        self.assertEqual(self.start("--emulator", emulator), 0, self.stderr)
        self.assertEqual(self.emulator()["ANDROID_SDK_ROOT"], sdk)

    def test_not_found(self):
        self.assertEqual(self.start(), 1)
        self.assertIn("Android Emulator is not found", self.stderr)

    def test_updated_zip(self):
        sdk = os.path.join(self.dir, "sdk")
        self.make_sdk(sdk)
        env = {"ANDROID_HOME": sdk}
        self.assertEqual(self.start(env=env), 0, self.stderr)
        userdata = os.path.join(self.rundir, "avd", self.name + ".avd",
                                "userdata-qemu.img")
        open(userdata, "w").close()
        self.assertEqual(self.start(env=env), 0, self.stderr)
        self.assertTrue(os.path.exists(userdata))
        zip_path = os.path.join(self.target,
                                "sdk-repo-linux-system-images.zip")
        future = time.time() + 10
        os.utime(zip_path, (future, future))
        self.assertEqual(self.start(env=env), 0, self.stderr)
        self.assertFalse(os.path.exists(userdata))

    def test_stop_is_not_supported(self):
        self.assertEqual(self.start("--stop"), 2)
        self.assertIn("not supported", self.stderr)
        self.assertEqual(self.start("--stop", "--target", "emulator"), 2)
        self.assertIn("not supported", self.stderr)

    def test_form_factors(self):
        sdk = os.path.join(self.dir, "sdk")
        self.make_sdk(sdk)
        for ff, tag, abi in (("phone", "default", "x86_64"),
                             ("auto", "android-automotive", "x86_64")):
            with self.subTest(form_factor=ff):
                self.name = "e-" + ff
                self.make_output(self.name, {"platform": "emulator",
                                             "form_factor": ff})
                self.rundir = os.path.realpath(os.path.join(
                    self.out, self.name, "run-emulator"))
                self.assertEqual(self.start(env={"ANDROID_HOME": sdk}), 0,
                                 self.stderr)
                config = self.config()
                self.assertEqual(config["tag.id"], tag)
                self.assertEqual(config["abi.type"], abi)
                self.assertEqual(config["hw.dPad"], "no")


if __name__ == "__main__":
    unittest.main()
