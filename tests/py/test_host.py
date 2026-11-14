"""Tests for build-aosp.sh with a stub docker command.

Ported from tests/test-build-aosp.sh. build-aosp.sh is run as a process, so
that the wrapper, the argument parsing and the exec of docker are tested.
"""
from __future__ import annotations

import json
import os
import pwd
import stat
import subprocess
import tempfile
import textwrap
import unittest

from helpers import REPODIR, has_yaml

# The stub records each invocation as a JSON line.
# "test -e" checks exit with $STUB_TEST_RC.
STUB = textwrap.dedent('''\
    #!/usr/bin/env python3
    import json, os, sys
    args = sys.argv[1:]
    with open(os.environ["STUB_LOG"], "a") as f:
        f.write(json.dumps(args) + "\\n")
    if args and args[-1].startswith("test -e "):
        sys.exit(int(os.environ.get("STUB_TEST_RC", "1")))
    if args[:2] == ["image", "inspect"]:
        print("sha256:fake")
    ''')


class HostTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        stubdir = os.path.join(self.dir, "stub")
        os.mkdir(stubdir)
        docker = os.path.join(stubdir, "docker")
        with open(docker, "w") as f:
            f.write(STUB)
        os.chmod(docker, os.stat(docker).st_mode | stat.S_IXUSR)
        self.var = os.path.join(self.dir, "var")
        self.out = os.path.join(self.dir, "out")
        os.mkdir(self.var)
        os.mkdir(self.out)
        self.log = os.path.join(self.dir, "docker.log")
        self.env = dict(os.environ, PATH=stubdir + ":" + os.environ["PATH"],
                        STUB_LOG=self.log, PYTHONDONTWRITEBYTECODE="1")
        self.env.pop("SUDO_USER", None)

    def tearDown(self):
        self.tmp.cleanup()

    def build_aosp(self, *args, env=None, cwd=None):
        e = dict(self.env)
        e.update(env or {})
        r = subprocess.run(["bash", os.path.join(REPODIR, "build-aosp.sh")]
                           + list(args), env=e, cwd=cwd,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True)
        self.stdout, self.stderr = r.stdout, r.stderr
        return r.returncode

    def rpi14(self, *args, **kwargs):
        return self.build_aosp("--rpi", "--android", "14",
                               "--workdir", self.var, "--outdir", self.out,
                               *args, **kwargs)

    def calls(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log) as f:
            return [json.loads(line) for line in f]

    def run_call(self):
        """The argv of the docker run of the build."""
        runs = [c for c in self.calls()
                if c[0] == "run" and not c[-1].startswith("test -e ")]
        self.assertEqual(len(runs), 1, self.calls())
        return runs[0]

    def envs(self, argv):
        return [argv[i + 1] for i, a in enumerate(argv) if a == "--env"]

    def mounts(self, argv):
        return [argv[i + 1] for i, a in enumerate(argv) if a == "-v"]

    def configs(self):
        return sorted(p for p in os.listdir(self.out)
                      if p.startswith("build-config-"))


class TestCompatibility(HostTestCase):
    def test_help(self):
        self.assertEqual(self.build_aosp("-h"), 0)
        self.assertIn("--no-gen", self.stdout)
        self.assertEqual(self.calls(), [])

    def test_empty_arch_is_default(self):
        self.assertEqual(self.rpi14("--arch", "", "build"), 0, self.stderr)
        self.assertIn("ARG_ARCH=", self.envs(self.run_call()))

    def test_unknown_user_without_adduser(self):
        self.assertEqual(self.rpi14("build", env={"USER": "no-such-user-x"}),
                         0, self.stderr)
        self.assertIn("/tmp/no-such-user-x/", self.run_call())

    def test_readme_example(self):
        self.assertEqual(self.rpi14("--arch", "arm64", "fetch", "patch",
                                    "build"), 0, self.stderr)
        argv = self.run_call()
        self.assertEqual(argv[:3], ["run", "--rm", "--pull=never"])
        self.assertEqual(argv[3:7], ["--init", "-it", "--userns=host",
                                     "--privileged"])
        self.assertEqual(self.envs(argv), [
            "ARG_ANDROID_VERSION=14", "ARG_RPI=rpi4", "ARG_ARCH=arm64",
            "ARG_NO_GEN=false", "CONTAINER_SRCDIR=/mnt/aosp"])
        user = os.environ.get("USER") or pwd.getpwuid(os.getuid()).pw_name
        self.assertIn("/tmp/%s/" % user, argv)
        var = os.path.realpath(self.var)
        self.assertEqual(self.mounts(argv), [
            REPODIR + "/src:/opt/mnt_src",
            var + "/kernel_work:/mnt/kernel_work",
            os.path.realpath(self.out) + ":/mnt/out",
            var + "/work:/mnt/aosp",
            var + "/gen:/mnt/gen",
            var + "/kernel_gen:/mnt/kernel_gen"])
        self.assertEqual(argv[-2], "env-aosp/focal:latest")
        self.assertEqual(argv[-1], "set -o pipefail; cp -ar /opt/mnt_src "
                         "/tmp/src && bash /tmp/src/start.sh fetch patch build")
        for d in ("work", "kernel_work", "gen", "kernel_gen"):
            self.assertTrue(os.path.isdir(os.path.join(self.var, d)))

    def test_arch_is_passed_as_given(self):
        self.assertEqual(self.rpi14("build"), 0, self.stderr)
        self.assertIn("ARG_ARCH=", self.envs(self.run_call()))

    def test_no_gen(self):
        self.assertEqual(self.rpi14("--no-gen", "build"), 0)
        argv = self.run_call()
        self.assertIn("ARG_NO_GEN=true", self.envs(argv))
        self.assertFalse(any(m.endswith(":/mnt/gen")
                             for m in self.mounts(argv)))

    def test_non_rpi(self):
        self.assertEqual(self.build_aosp(
            "--android", "14", "--arch", "x86_64", "--workdir", self.var,
            "--outdir", self.out, "build"), 0, self.stderr)
        self.assertIn("ARG_RPI=", self.envs(self.run_call()))

    def test_intermixed_options_and_tasks(self):
        self.assertEqual(self.build_aosp(
            "fetch", "--rpi", "--android", "14", "--workdir", self.var,
            "patch", "--outdir", self.out, "build"), 0, self.stderr)
        self.assertTrue(self.run_call()[-1].endswith(
            "start.sh fetch patch build"))

    def test_adduser(self):
        self.assertEqual(self.rpi14("--adduser", "build"), 0)
        envs = self.envs(self.run_call())
        self.assertEqual([e.split("=")[0] for e in envs[-3:]],
                         ["USER_", "UID_", "GID_"])
        self.assertIn("UID_=%d" % os.getuid(), envs)

    def test_path_with_space(self):
        var = os.path.join(self.dir, "my var")
        os.mkdir(var)
        self.assertEqual(self.build_aosp(
            "--rpi", "--android", "14", "--workdir", var,
            "--outdir", self.out, "build"), 0, self.stderr)
        self.assertIn(os.path.realpath(var) + "/work:/mnt/aosp",
                      self.mounts(self.run_call()))

    def test_relative_paths_from_cwd(self):
        self.assertEqual(self.build_aosp(
            "--rpi", "--android", "14", "--workdir", "var",
            "--outdir", "out", "build", cwd=self.dir), 0, self.stderr)
        self.assertIn(os.path.realpath(self.var) + "/work:/mnt/aosp",
                      self.mounts(self.run_call()))

    def test_never_pulls(self):
        self.assertEqual(self.rpi14("--mount-same", "build"), 0)
        runs = [c for c in self.calls() if c[0] == "run"]
        self.assertEqual(len(runs), 2)
        for c in runs:
            self.assertEqual(c[1:3], ["--rm", "--pull=never"])


class TestErrors(HostTestCase):
    def assertError(self, rc, message):
        self.assertEqual(rc, 2, self.stderr)
        self.assertIn(message, self.stderr)
        self.assertEqual(self.calls(), [])

    def test_android_required(self):
        self.assertError(self.build_aosp("--workdir", self.var, "--outdir",
                                         self.out, "build"),
                         "--android is required. e.g. '10'.")

    def test_android_unsupported(self):
        self.assertError(self.build_aosp(
            "--android", "13", "--workdir", self.var, "--outdir", self.out,
            "build"), "The android version '13' is not supported.")

    def test_missing_value(self):
        self.assertError(self.build_aosp("--android"), "expected one argument")

    def test_abbreviation(self):
        self.assertError(self.build_aosp("--and", "14"), "unrecognized")

    def test_unknown_option(self):
        self.assertError(self.rpi14("--foo", "build"), "unrecognized")

    def test_unknown_task(self):
        self.assertError(self.rpi14("bulid"), "Unknown task: bulid")

    def test_no_task(self):
        self.assertError(self.rpi14(), "No task is specified.")

    def test_workdir(self):
        self.assertError(self.build_aosp("--android", "14", "--outdir",
                                         self.out, "build"),
                         "--workdir is required.")
        self.assertError(self.build_aosp(
            "--android", "14", "--workdir", self.dir + "/none",
            "--outdir", self.out, "build"), "The workdir '%s/none' does not "
            "exist." % self.dir)

    def test_outdir(self):
        self.assertError(self.build_aosp("--android", "14", "--workdir",
                                         self.var, "build"),
                         "--outdir is required.")

    def test_empty_values(self):
        # An empty value is "not specified", as in the old script.
        self.assertError(self.build_aosp("--android", "14", "--workdir", "",
                                         "--outdir", self.out, "build"),
                         "--workdir is required.")
        self.assertError(self.build_aosp("--android", "", "--workdir",
                                         self.var, "--outdir", self.out,
                                         "build"),
                         "--android is required.")

    def test_relative_path_is_shown_as_given(self):
        self.assertError(self.build_aosp("--android", "14", "--workdir",
                                         "none", "--outdir", self.out,
                                         "build", cwd=self.dir),
                         "The workdir 'none' does not exist.")

    @unittest.skipUnless(has_yaml(), "PyYAML is not installed")
    def test_missing_config_file(self):
        self.assertError(self.rpi14("--config", self.dir + "/none.yaml",
                                    "build"), "none.yaml")

    def test_unknown_user_with_adduser(self):
        self.assertEqual(self.rpi14("--adduser", "build",
                                    env={"USER": "no-such-user-x"}), 1)
        self.assertIn("unknown user", self.stderr)
        self.assertNotIn("Traceback", self.stderr)

    def test_arch_before_docker(self):
        self.assertError(self.rpi14("--arch", "arm", "build"),
                         "error: Android 14 for RPi supports only arm64.")
        self.assertError(self.rpi14("--arch", "aarch64", "build"),
                         "error: unsupported arch: aarch64")


class TestDaemon(HostTestCase):
    def run_container_command(self, rc):
        """Run the command in the container with a fake start.sh."""
        fake = os.path.join(self.dir, "fake")
        subprocess.run(["rm", "-rf", fake])
        os.makedirs(fake + "/mnt_src")
        os.makedirs(fake + "/out")
        with open(fake + "/mnt_src/start.sh", "w") as f:
            f.write("echo running\nexit %d\n" % rc)
        cmd = (self.run_call()[-1]
               .replace("/opt/mnt_src", fake + "/mnt_src")
               .replace("/tmp/src", fake + "/src")
               .replace("/mnt/out", fake + "/out"))
        env = {k: v for k, v in os.environ.items()
               if k not in ("USER_", "UID_", "GID_")}
        # Run it through the entrypoint of the docker image.
        r = subprocess.run(["sh", REPODIR + "/base/entrypoint.sh", cmd],
                           env=env, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL)
        logs = [p for p in os.listdir(fake + "/out")
                if p.startswith("console-")]
        self.assertEqual(len(logs), 1)
        with open(os.path.join(fake, "out", logs[0])) as f:
            return r.returncode, f.read()

    def test_daemon(self):
        self.assertEqual(self.rpi14("--daemon", "build"), 0, self.stderr)
        argv = self.run_call()
        self.assertEqual(argv[3:6], ["-d", "--userns=host", "--privileged"])
        self.assertIn("| tee /mnt/out/console-", argv[-1])
        # The message is flushed before exec.
        self.assertIn("The log will be written to %s/console-"
                      % os.path.realpath(self.out), self.stdout)

        for code in (3, 0):
            rc, log = self.run_container_command(code)
            self.assertEqual(rc, code)
            self.assertEqual(log.splitlines(),
                             ["running", "exit status: %d" % code])

    def test_timestamp_of_log_and_config(self):
        self.assertEqual(self.rpi14("--daemon", "build"), 0)
        ts = self.run_call()[-1].split("console-")[1].split(".log")[0]
        self.assertEqual(self.configs(), ["build-config-%s.json" % ts])

    def test_foreground_failure_is_propagated(self):
        self.assertEqual(self.rpi14("build"), 0)
        fake = os.path.join(self.dir, "fake")
        os.makedirs(fake + "/mnt_src")
        with open(fake + "/mnt_src/start.sh", "w") as f:
            f.write("exit 3\n")
        cmd = (self.run_call()[-1]
               .replace("/opt/mnt_src", fake + "/mnt_src")
               .replace("/tmp/src", fake + "/src"))
        env = {k: v for k, v in os.environ.items()
               if k not in ("USER_", "UID_", "GID_")}
        r = subprocess.run(["sh", REPODIR + "/base/entrypoint.sh", cmd],
                           env=env, stdout=subprocess.DEVNULL)
        self.assertEqual(r.returncode, 3)


class TestMountSame(HostTestCase):
    def test_not_used(self):
        self.assertEqual(self.rpi14("--mount-same", "build",
                                    env={"STUB_TEST_RC": "1"}), 0)
        var = os.path.realpath(self.var)
        argv = self.run_call()
        self.assertIn("CONTAINER_SRCDIR=%s/work" % var, self.envs(argv))
        self.assertIn("%s/work:%s/work" % (var, var), self.mounts(argv))

    def test_already_used(self):
        self.assertEqual(self.rpi14("--mount-same", "build",
                                    env={"STUB_TEST_RC": "0"}), 1)
        self.assertIn("already in use", self.stderr)
        self.assertEqual(self.configs(), [])

    def test_docker_failure(self):
        self.assertEqual(self.rpi14("--mount-same", "build",
                                    env={"STUB_TEST_RC": "125"}), 1)
        self.assertIn("Failed to run the docker image", self.stderr)


class TestResolvedConfig(HostTestCase):
    def test_written(self):
        self.assertEqual(self.rpi14("build"), 0)
        [name] = self.configs()
        path = os.path.join(self.out, name)
        self.assertEqual(stat.S_IMODE(os.stat(path).st_mode), 0o644)
        with open(path) as f:
            data = json.load(f)
        self.assertEqual(data["lunch_choice"], "rpi4_tv-userdebug")
        self.assertEqual(data["container_srcdir"], "/mnt/aosp")
        self.assertEqual(data["record"]["image_id"], "sha256:fake")
        self.assertRegex(data["record"]["tool_revision"], r"^[0-9a-f]{40,}$")
        self.assertIn(data["record"]["tool_dirty"], (True, False))

    def test_print_config(self):
        self.assertEqual(self.rpi14("--print-config"), 0, self.stderr)
        data = json.loads(self.stdout)
        self.assertEqual(data["android_version"], "14")
        self.assertEqual(data["build_env"]["SKIP_ABI_CHECKS"], "true")
        self.assertIsNone(data["record"]["image_id"])
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.configs(), [])
        self.assertEqual(self.stderr, "")

    def test_print_config_with_mount_same(self):
        self.assertEqual(self.rpi14("--mount-same", "--print-config"), 0)
        data = json.loads(self.stdout)
        self.assertEqual(data["container_srcdir"],
                         os.path.realpath(self.var) + "/work")
        self.assertIn("not checked", self.stderr)
        self.assertEqual(self.calls(), [])


@unittest.skipUnless(has_yaml(), "PyYAML is not installed")
class TestConfigFile(HostTestCase):
    def write_config(self, text):
        path = os.path.join(self.dir, "c.yaml")
        with open(path, "w") as f:
            f.write(textwrap.dedent(text))
        return path

    def test_config_only(self):
        path = self.write_config("""
            schema: 1
            android: 14
            rpi: true
            workdir: var
            outdir: out
            gen: false
        """)
        # Relative paths are from the config file, not from the cwd.
        self.assertEqual(self.build_aosp("--config", path, "build", cwd="/"),
                         0, self.stderr)
        argv = self.run_call()
        self.assertIn("ARG_NO_GEN=true", self.envs(argv))
        self.assertIn(os.path.realpath(self.var) + "/work:/mnt/aosp",
                      self.mounts(argv))

    def test_cli_overrides(self):
        path = self.write_config("""
            schema: 1
            android: 12
            rpi: true
            workdir: var
            outdir: out
            gen: false
        """)
        self.assertEqual(self.build_aosp("--config", path, "--android", "14",
                                         "--gen", "build"), 0, self.stderr)
        envs = self.envs(self.run_call())
        self.assertIn("ARG_ANDROID_VERSION=14", envs)
        self.assertIn("ARG_NO_GEN=false", envs)

    def test_cli_overrides_arch_and_mount_same(self):
        path = self.write_config("""
            schema: 1
            android: 11
            rpi: true
            arch: arm
            workdir: var
            outdir: out
            mount_same: true
        """)
        self.assertEqual(self.build_aosp("--config", path, "--arch", "arm64",
                                         "--no-mount-same", "build"),
                         0, self.stderr)
        argv = self.run_call()
        self.assertIn("ARG_ARCH=arm64", self.envs(argv))
        self.assertIn("CONTAINER_SRCDIR=/mnt/aosp", self.envs(argv))
        self.assertEqual(len([c for c in self.calls() if c[0] == "run"]), 1)

    def test_invalid_config(self):
        path = self.write_config("schema: 1\ndaemon: true\n")
        self.assertEqual(self.build_aosp("--config", path, "build"), 2)
        self.assertIn("daemon", self.stderr)
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
