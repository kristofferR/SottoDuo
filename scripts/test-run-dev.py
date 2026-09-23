#!/usr/bin/env python3
"""Check runner process/port tracking in isolation, without models or networking."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import threading


def main():
    source = Path(__file__).resolve().parent / "run-dev.sh"
    with tempfile.TemporaryDirectory(prefix="sottoduo-runner-test-") as temporary:
        root = Path(temporary)
        scripts = root / "scripts"
        scripts.mkdir()
        shutil.copy2(source, scripts / "run-dev.sh")
        binary = root / "build/server/sottoduo-server"
        binary.parent.mkdir(parents=True)
        # A real owned process lets the runner use its actual kill/ps checks.
        c_source = root / "server.c"
        c_source.write_text("#include <unistd.h>\nint main(void) { for (;;) pause(); }\n")
        subprocess.run(["cc", str(c_source), "-o", str(binary)], check=True)
        client = root / "build/SottoDuo Dev.app/Contents/MacOS/SottoDuo"
        client.parent.mkdir(parents=True)
        client.touch(mode=0o700)
        model = root / "model"
        model.touch()
        mocks = root / "mock-bin"
        mocks.mkdir()
        calls = root / "calls"
        calls.write_text("")
        for name, body in {
            "uname": "printf 'Darwin\\n'",
            "curl": 'printf "curl %s\\n" "$*" >> "$RUNNER_TEST_CALLS"',
            "open": 'printf "open %s\\n" "$*" >> "$RUNNER_TEST_CALLS"',
        }.items():
            executable = mocks / name
            executable.write_text("#!/bin/bash\n" + body + "\n")
            executable.chmod(0o700)
        environment = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("SOTTODUO_", "SOTTO_"))
        }
        environment.update({
            "PATH": str(mocks) + os.pathsep + os.environ["PATH"],
            "RUNNER_TEST_CALLS": str(calls),
            "SOTTODUO_SPEECH_MODEL": str(model),
            "SOTTODUO_TEXT_MODEL": str(model),
        })
        pid_file = root / ".local/server.pid"
        tracked_pid = None

        def run(action, port=None, success=True):
            env = environment.copy()
            if port is not None:
                env["SOTTODUO_SERVER_PORT"] = port
            calls.write_text("")
            result = subprocess.run(
                ["bash", str(scripts / "run-dev.sh"), action, "--skip-build"],
                env=env, capture_output=True, text=True, timeout=15,
            )
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return result.stdout + result.stderr, calls.read_text()

        try:
            output, invoked = run("start", "8493")
            fields = pid_file.read_text().split()
            tracked_pid = int(fields[0])
            assert len(fields) == 2 and fields[1] == "8493", fields
            assert "http://127.0.0.1:8493/v1/health" in invoked, invoked
            assert "SOTTODUO_SERVER_URL=http://127.0.0.1:8493" in invoked, invoked

            for requested in [None, "8494", "invalid"]:
                output, invoked = run("status", requested)
                assert "http://localhost:8493" in output, output
                assert "http://127.0.0.1:8493/v1/health" in invoked, invoked
                output, invoked = run("start", requested)
                assert "already running" in output, output
                assert "SOTTODUO_SERVER_URL=http://127.0.0.1:8493" in invoked, invoked
                assert int(pid_file.read_text().split()[0]) == tracked_pid

            pid_file.write_text(f"{tracked_pid}\n")
            output, invoked = run("status")
            assert "http://127.0.0.1:8493/v1/health" in invoked, invoked

            for invalid in ["0", "65536", "garbage", "8494", "8493 extra"]:
                pid_file.write_text(f"{tracked_pid} {invalid}\n")
                for action in ["status", "start"]:
                    output, invoked = run(action, success=False)
                    assert "Cannot verify" in output, output
                    assert not invoked, invoked
                os.kill(tracked_pid, 0)

            # Stop remains available even if endpoint metadata is damaged.
            run("stop")
            assert not pid_file.exists()
            tracked_pid = None

            environment["SOTTO_SPEECH_MODEL"] = str(model)
            environment["SOTTO_TEXT_MODEL"] = str(model)
            del environment["SOTTODUO_SPEECH_MODEL"]
            del environment["SOTTODUO_TEXT_MODEL"]
            run("start", "8493")
            tracked_pid = int(pid_file.read_text().split()[0])
            command = subprocess.check_output(["ps", "-p", str(tracked_pid), "-o", "command="], text=True)
            assert f"--speech-model {model}" in command and f"--proof-model {model}" in command, command
            run("stop")
            tracked_pid = None

            environment.update({
                "SOTTO_SERVER_PORT": "8495",
                "SOTTO_SERVER_DATA_DIR": str(root / "legacy-data"),
                "SOTTO_ENGINE_PATH": str(root / "legacy-engine"),
                "SOTTO_TEXT_ENGINE_PATH": str(root / "legacy-text-engine"),
                "SOTTO_VAD_PATH": str(root / "legacy-vad"),
                "SOTTO_SERVER_TOKEN_FILE": str(root / "legacy-token"),
            })
            run("start")
            tracked_pid = int(pid_file.read_text().split()[0])
            command = subprocess.check_output(["ps", "-p", str(tracked_pid), "-o", "command="], text=True)
            for expected in [
                "--port 8495", f"--data-dir {root / 'legacy-data'}",
                f"--speech-helper {root / 'legacy-engine'}",
                f"--proof-helper {root / 'legacy-text-engine'}",
                f"--vad-model {root / 'legacy-vad'}",
                f"--token-file {root / 'legacy-token'}",
            ]:
                assert expected in command, (expected, command)
            run("stop")
            tracked_pid = None

            environment["SOTTODUO_SERVER_PORT"] = "8496"
            environment["SOTTODUO_SERVER_DATA_DIR"] = str(root / "new-data")
            run("start")
            tracked_pid = int(pid_file.read_text().split()[0])
            command = subprocess.check_output(["ps", "-p", str(tracked_pid), "-o", "command="], text=True)
            assert "--port 8496" in command and f"--data-dir {root / 'new-data'}" in command, command
            run("stop")
            tracked_pid = None

            legacy_binary = root / "build/server/sotto-server"
            subprocess.run(["cc", str(c_source), "-o", str(legacy_binary)], check=True)
            legacy = subprocess.Popen([
                str(legacy_binary), "--host", "127.0.0.1", "--port", "8493",
            ])
            threading.Thread(target=legacy.wait, daemon=True).start()
            tracked_pid = legacy.pid
            pid_file.write_text(f"{tracked_pid} 8493\n")
            output, invoked = run("status")
            assert "http://localhost:8493" in output, output
            output, invoked = run("start")
            assert "already running" in output, output
            assert int(pid_file.read_text().split()[0]) == tracked_pid
            run("stop")
            assert not pid_file.exists()
            tracked_pid = None

            # A reused PID must not be probed or stopped. Use this test process.
            pid_file.write_text(f"{os.getpid()} 8493\n")
            output, invoked = run("status")
            assert "stopped" in output and not invoked, (output, invoked)
            run("stop")
            assert not pid_file.exists()

            finished = subprocess.Popen(["true"])
            finished.wait()
            pid_file.write_text(f"{finished.pid} 8493\n")
            output, invoked = run("status")
            assert "stopped" in output and not invoked, (output, invoked)
            run("stop")
            assert not pid_file.exists()

            for invalid in ["0", "65536", "garbage"]:
                output, invoked = run("start", invalid, success=False)
                assert "must be an integer" in output and not invoked, (output, invoked)
                assert not pid_file.exists()
        finally:
            if tracked_pid is not None:
                try:
                    os.kill(tracked_pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
    print("Dev runner process/port checks passed.")


if __name__ == "__main__":
    main()
