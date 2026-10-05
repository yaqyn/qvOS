#!/usr/bin/python3
"""Exercise the public sh bootstrap with real pipes and a controlling PTY."""
import hashlib
import io
import os
import pathlib
import pty
import select
import shlex
import subprocess
import tarfile
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE_HASH = "a" * 64


class LauncherTests(unittest.TestCase):
  def setUp(self):
    self.tmp = tempfile.TemporaryDirectory()
    self.addCleanup(self.tmp.cleanup)
    self.root = pathlib.Path(self.tmp.name)
    tools = self.root / "tools"
    tools.mkdir()
    self.env = dict(os.environ, PATH=f"{tools}:/usr/bin:/bin", TMPDIR=str(self.root))
    fake = tools / "curl"
    fake.write_text('#!/bin/bash\nset -eu\nwhile (($#)); do\n'
                    '  if [[ $1 == "-o" ]]; then cp "$FIXTURE_ARCHIVE" "$2"; exit; fi\n'
                    '  shift\ndone\nexit 1\n')
    fake.chmod(0o700)

  def fixture(self, *, tamper=False, wrong_digest=False):
    digest = "b" * 64 if wrong_digest else SOURCE_HASH
    binary = (f'#!/bin/bash\nif [[ ${{1:-}} == "--source-hash" ]]; then echo {digest}; exit; fi\n'
              'echo INPUT_READY\nread -r answer\n[[ $answer == "keyboard" ]] || exit 9\n'
              'echo INTERACTIVE_OK\n')
    archive = self.root / "fixture.tar.gz"
    with tarfile.open(archive, "w:gz") as output:
      for name, data in {"qvos-tui": binary, "build": "#!/bin/bash\nexit 0\n"}.items():
        entry = tarfile.TarInfo(name)
        entry.size = len(data.encode())
        entry.mode = 0o700
        output.addfile(entry, io.BytesIO(data.encode()))
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    script = (ROOT / "release/launcher/bootstrap.sh").read_text()
    for key, value in {"ORIGIN": "https://fixture.invalid", "ARCHIVE": "fixture.tar.gz",
                       "ARCHIVE_SHA256": checksum, "SOURCE_HASH": SOURCE_HASH}.items():
      script = script.replace("@" + key + "@", value)
    self.script = self.root / "launcher.sh"
    self.script.write_text(script)
    self.env["FIXTURE_ARCHIVE"] = str(archive)
    if tamper:
      archive.write_bytes(archive.read_bytes() + b"tampered")

  def run_pty(self):
    pid, fd = pty.fork()
    if pid == 0:
      os.execve("/bin/sh", ["sh", "-c", f"cat {shlex.quote(str(self.script))} | sh"], self.env)
    self.addCleanup(os.close, fd)
    output = bytearray()
    sent = False
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
      ready, _, _ = select.select([fd], [], [], 0.1)
      if ready:
        try:
          data = os.read(fd, 65536)
        except OSError:
          break
        if not data:
          break
        output.extend(data)
        if b"INPUT_READY" in output and not sent:
          os.write(fd, b"keyboard\n")
          sent = True
    else:
      os.kill(pid, 9)
      self.fail("bootstrap stalled")
    _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status), output.decode(errors="replace")

  def test_pipe_reconnects_keyboard_and_cleans_payload(self):
    self.fixture()
    status, output = self.run_pty()
    self.assertEqual(status, 0, output)
    self.assertIn("INTERACTIVE_OK", output)
    self.assertEqual(list(self.root.glob("qvos-launcher.*")), [])

  def test_tampered_download_never_executes(self):
    self.fixture(tamper=True)
    status, output = self.run_pty()
    self.assertNotEqual(status, 0, output)
    self.assertIn("integrity check", output)
    self.assertNotIn("INPUT_READY", output)
    self.assertEqual(list(self.root.glob("qvos-launcher.*")), [])

  def test_wrong_binary_provenance_never_opens_ui(self):
    self.fixture(wrong_digest=True)
    status, output = self.run_pty()
    self.assertNotEqual(status, 0, output)
    self.assertIn("does not match", output)
    self.assertNotIn("INPUT_READY", output)

  def test_noninteractive_shell_reports_terminal_requirement(self):
    self.fixture()
    result = subprocess.run(["/bin/sh", str(self.script)], env=self.env,
                            capture_output=True, start_new_session=True)
    self.assertNotEqual(result.returncode, 0)
    self.assertIn(b"interactive terminal", result.stderr)


class BuildHandoffTests(unittest.TestCase):
  def test_build_checks_prerequisites_and_delegates_matching_source(self):
    with tempfile.TemporaryDirectory() as temporary:
      root = pathlib.Path(temporary)
      tools = root / "tools"
      tools.mkdir()
      fixture = root / "source"
      (fixture / "qvcore/tui").mkdir(parents=True)
      (fixture / "release/iso").mkdir(parents=True)
      files = {
        tools / "docker": '#!/bin/bash\n[[ ${DOCKER_READY:-} == "yes" ]]\n',
        tools / "git": '#!/bin/bash\nif [[ $* == *clone* ]]; then cp -a "$SOURCE_FIXTURE" "${@: -1}"; else echo ' + "c" * 40 + '\nfi\n',
        fixture / "qvcore/tui/source-hash": '#!/bin/bash\necho "$FIXTURE_DIGEST"\n',
        fixture / "release/iso/build": '#!/bin/bash\necho "DELEGATED:$*"\n[[ $QVOS_SOURCE_REPO == "$QVOS_PATH" ]]\n',
      }
      for path, contents in files.items():
        path.write_text(contents)
        path.chmod(0o700)
      environment = dict(os.environ, PATH=f"{tools}:/usr/bin:/bin", TMPDIR=str(root),
                         SOURCE_FIXTURE=str(fixture), FIXTURE_DIGEST=SOURCE_HASH,
                         QVOS_LAUNCHER_SOURCE_HASH=SOURCE_HASH)
      command = [str(ROOT / "release/launcher/build"), "--allow-downloads", "--prepare-only"]
      refused = subprocess.run(command, env=environment, capture_output=True)
      self.assertNotEqual(refused.returncode, 0)
      self.assertIn(b"Docker must be running", refused.stderr)
      environment["DOCKER_READY"] = "yes"
      result = subprocess.run(command, env=environment, capture_output=True)
      self.assertEqual(result.returncode, 0, result.stderr)
      self.assertIn(b"DELEGATED:--allow-downloads --prepare-only", result.stdout)
      self.assertEqual(list(root.glob("qvos-build-source.*")), [])
      environment["FIXTURE_DIGEST"] = "b" * 64
      refused = subprocess.run(command, env=environment, capture_output=True)
      self.assertNotEqual(refused.returncode, 0)
      self.assertIn(b"Relaunch qvOS", refused.stderr)
      self.assertNotIn(b"DELEGATED", refused.stdout)
      self.assertEqual(list(root.glob("qvos-build-source.*")), [])


if __name__ == "__main__":
  unittest.main()
