"""build-aosp.sh: fetch and build AOSP on docker. Runs on the host.

The tasks in the container are the shell scripts (src/container/start.sh).
The resolved configuration is written to <outdir>/build-config-<timestamp>.json
and the container reads it. It is also kept as a record.
"""
from __future__ import annotations

import argparse
import datetime
import os
import pwd
import shlex
import subprocess
import sys
import tempfile
from typing import List, Optional

from aosp_build import ConfigError, config_file, versions
from aosp_build.fields import FIELDS, normalize, merge
from aosp_build.schema import SCHEMA, ResolvedConfig

DIST_CODENAME = "focal"
IMAGE_NAME = "env-aosp/%s:latest" % DIST_CODENAME
TASKS = ("fetch", "patch", "build", "patch-revert", "bash")

# src/host/aosp_build/host.py -> the root of the repository.
REPODIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
# The files of the tool whose changes make the record dirty.
TOOL_PATHS = ("build-aosp.sh", "src", "docker")


class Exit(Exception):
    def __init__(self, code: int, message: Optional[str] = None):
        super().__init__(message)
        self.code = code
        self.message = message


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="build-aosp.sh", allow_abbrev=False,
        usage="%(prog)s [OPTION...] task1 task2 ...",
        description="Fetch and build AOSP on docker.",
        epilog="available tasks: fetch (fetch sources from the repository), "
               "patch (apply patches), build (build sources), "
               "patch-revert (revert patches), bash (run a shell instead)")
    parser.add_argument(
        "--config", metavar="FILE",
        help="Read the parameters from the INI file. Command line options "
             "override it. See build-aosp.example.ini.")
    parser.add_argument(
        "--print-config", action="store_true",
        help="Print the resolved configuration as JSON and exit. "
             "Docker is not run.")
    for f in FIELDS:
        if f.cli is None:
            continue
        if f.type == "bool":
            parser.add_argument(f.cli, dest=f.key, action="store_const",
                                const=True, default=None, help=f.help)
            if f.cli_negate:
                parser.add_argument(f.cli_negate, dest=f.key,
                                    action="store_const", const=False,
                                    default=None,
                                    help="The opposite of %s." % f.cli)
        else:
            parser.add_argument(f.cli, dest=f.key, metavar=f.metavar,
                                default=None, help=f.help)
    # No choices: on Python <= 3.11 they reject an empty list of tasks.
    parser.add_argument("tasks", nargs="*", metavar="task",
                        help=argparse.SUPPRESS)
    return parser


def _check_dir(value: Optional[str], shown: Optional[str], option: str,
               name: str) -> str:
    """shown: the value as the user wrote it on the command line, if any."""
    if not value:
        raise Exit(2, "%s is required." % option)
    path = os.path.realpath(value)
    if not os.path.isdir(path):
        raise Exit(2, "The %s '%s' does not exist." % (name, shown or value))
    return path


def parse_config(argv: List[str]) -> tuple:
    """Return (merged values, tasks, args). Raises Exit or ConfigError."""
    args = build_parser().parse_intermixed_args(argv)
    cwd = os.getcwd()
    cli = {}
    for f in FIELDS:
        if f.cli is not None:
            cli[f.key] = normalize(f, getattr(args, f.key), cwd)
    file_values = config_file.load(args.config) if args.config else {}
    values = merge(cli, file_values)

    for task in args.tasks:
        if task not in TASKS:
            raise Exit(2, "Unknown task: %s" % task)

    # --rpi is the same as --platform rpi4. Conflicting values are errors,
    # not "the last one wins" (also between the command line and the file).
    if values["rpi"] and values["platform"] not in (None, "rpi4"):
        raise Exit(2, "--rpi (rpi = true) conflicts with --platform %s. "
                   "Use --no-rpi to override rpi = true in the config file."
                   % values["platform"])
    if values["platform"] == "rpi4":
        values["rpi"] = True

    if values["android"] is None:
        raise Exit(2, "--android is required. e.g. '10'.")
    if values["android"] not in versions.VERSIONS:
        raise Exit(2, "The android version '%s' is not supported."
                   % values["android"])
    values["workdir"] = _check_dir(values["workdir"], args.workdir,
                                   "--workdir", "workdir")
    values["outdir"] = _check_dir(values["outdir"], args.outdir,
                                  "--outdir", "outdir")
    if not args.tasks and not args.print_config:
        raise Exit(2, "No task is specified.")
    return values, args.tasks, args


def check_mount_same(srcdir: str) -> None:
    """Fail if srcdir is already used in the image."""
    try:
        rc = subprocess.run(["docker", "run", "--rm", "--pull=never",
                             IMAGE_NAME,
                             "test -e %s" % shlex.quote(srcdir)]).returncode
    except OSError as e:
        raise Exit(1, "error: Failed to run docker: %s" % e)
    # 0: exists, 1: does not exist, others: docker itself failed
    if rc == 0:
        raise Exit(1, "error: '%s' is already in use in the docker container."
                   % srcdir)
    if rc != 1:
        raise Exit(1, "error: Failed to run the docker image '%s' "
                   "(exit code %d)." % (IMAGE_NAME, rc))


def _output(argv: List[str]) -> Optional[str]:
    try:
        r = subprocess.run(argv, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, universal_newlines=True)
    except OSError:
        return None
    return r.stdout.strip() if r.returncode == 0 else None


def make_record(timestamp: str, with_image: bool) -> dict:
    """Best-effort record of the tool and the image. Never fails."""
    revision = _output(["git", "-C", REPODIR, "rev-parse", "HEAD"])
    # --no-optional-locks: do not refresh .git/index (it may become
    # root-owned under sudo).
    # Only the files of the tool, including untracked ones (new scripts).
    status = _output(["git", "--no-optional-locks", "-C", REPODIR, "status",
                      "--porcelain", "--", *TOOL_PATHS])
    image_id = None
    if with_image:
        image_id = _output(["docker", "image", "inspect", "-f", "{{.Id}}",
                            IMAGE_NAME])
    return {
        "tool_revision": revision,
        "tool_dirty": None if status is None else status != "",
        "image_id": image_id,
        "created": timestamp,
    }


def write_config(path: str, config: ResolvedConfig) -> None:
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path),
                               prefix=".build-config-")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(config.to_json())
        # Readable by the user in the container even if written by root.
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def run(argv: List[str]) -> int:
    values, tasks, args = parse_config(argv)
    resolved = versions.resolve(values["android"], values["rpi"],
                                values["arch"], values["platform"],
                                values["form_factor"])

    workdir = values["workdir"]
    outdir = values["outdir"]
    work_sourcedir = os.path.join(workdir, "work")
    work_kernel_sourcedir = os.path.join(workdir, "kernel_work")
    work_gendir = os.path.join(workdir, "gen")
    work_kernel_gendir = os.path.join(workdir, "kernel_gen")
    use_gen = values["gen"]
    container_srcdir = work_sourcedir if values["mount_same"] else "/mnt/aosp"
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

    def resolved_config(record: dict) -> ResolvedConfig:
        return ResolvedConfig(schema=SCHEMA, use_gen=use_gen,
                              container_srcdir=container_srcdir,
                              record=record, **resolved)

    if args.print_config:
        if values["mount_same"]:
            print("note: --mount-same is not checked by --print-config. "
                  "container_srcdir is the value used when the check "
                  "succeeds.", file=sys.stderr)
        sys.stdout.write(resolved_config(
            make_record(timestamp, with_image=False)).to_json())
        return 0

    user = os.environ.get("SUDO_USER") or os.environ.get("USER") \
        or pwd.getpwuid(os.getuid()).pw_name

    try:
        # TODO: chown? chmod?
        os.makedirs(work_sourcedir, exist_ok=True)
        os.makedirs(work_kernel_sourcedir, exist_ok=True)
        if use_gen:
            os.makedirs(work_gendir, exist_ok=True)
            os.makedirs(work_kernel_gendir, exist_ok=True)
    except OSError as e:
        raise Exit(1, "error: %s" % e)

    if values["mount_same"]:
        check_mount_same(work_sourcedir)

    # The container reads the resolved config (src/container/config_env.py),
    # not environment variables. Not to change the environment of the build,
    # the path is given to start.sh as an argument.
    config_name = "build-config-%s.json" % timestamp
    config_path = os.path.join(outdir, config_name)
    options = ["-w", "/tmp/%s/" % user]
    if values["adduser"]:
        try:
            pw = pwd.getpwnam(user)
        except KeyError:
            raise Exit(1, "error: unknown user: %s" % user)
        options += ["--env", "USER_=%s" % user,
                    "--env", "UID_=%d" % pw.pw_uid,
                    "--env", "GID_=%d" % pw.pw_gid]

    srcdir = os.path.join(REPODIR, "src")
    mounts = [
        # Only src/container and src/common. src/host is not passed.
        "-v", "%s:/opt/mnt_src/container" % os.path.join(srcdir, "container"),
        "-v", "%s:/opt/mnt_src/common" % os.path.join(srcdir, "common"),
        "-v", "%s:/mnt/kernel_work" % work_kernel_sourcedir,
        "-v", "%s:/mnt/out" % outdir,
        "-v", "%s:%s" % (work_sourcedir, container_srcdir),
    ]
    if use_gen:
        mounts += ["-v", "%s:/mnt/gen" % work_gendir,
                   "-v", "%s:/mnt/kernel_gen" % work_kernel_gendir]

    command = ("set -o pipefail; cp -ar /opt/mnt_src /tmp/src && "
               "bash /tmp/src/container/start.sh "
               "--resolved-config /mnt/out/%s %s"
               % (config_name, " ".join(tasks)))

    if values["daemon"]:
        docker_options = ["-d"]
        logfile = "/mnt/out/console-%s.log" % timestamp
        # The container is removed after exit (--rm), so record the status.
        command += (" 2>&1 | tee %s; L_RC=$?; echo \"exit status: $L_RC\" "
                    ">> %s; exit $L_RC" % (logfile, logfile))
        print("The log will be written to %s"
              % os.path.join(outdir, "console-%s.log" % timestamp))
    else:
        docker_options = ["--init", "-it"]

    # Commonize the user namespace.
    # --privileged is required by nsjail, the build sandbox of soong. Without
    # it, soong disables sandboxing and the build behaves differently. The
    # risk is limited on rootless docker, which is the expected environment.
    docker_options += ["--userns=host", "--privileged"]

    try:
        write_config(config_path,
                     resolved_config(make_record(timestamp, with_image=True)))
    except OSError as e:
        raise Exit(1, "error: Failed to write the config: %s" % e)

    docker_argv = (["docker", "run", "--rm", "--pull=never"] + docker_options
                   + options + mounts + [IMAGE_NAME, command])
    # The output is lost by exec unless it is flushed.
    sys.stdout.flush()
    sys.stderr.flush()
    try:
        os.execvp("docker", docker_argv)
    except OSError as e:
        # Do not leave the record of a run that did not start.
        os.unlink(config_path)
        raise Exit(127, "error: Failed to run docker: %s" % e)
    return 127  # not reached


def main(argv: Optional[List[str]] = None) -> int:
    try:
        return run(sys.argv[1:] if argv is None else argv)
    except ConfigError as e:
        print("error: %s" % e, file=sys.stderr)
        return 2
    except Exit as e:
        if e.message:
            print(e.message, file=sys.stderr)
        return e.code
