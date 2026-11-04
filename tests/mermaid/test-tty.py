"""A synthetic PTY tests the actual ioctl without touching the user's terminal."""
import fcntl
import os
import pty
import struct
import subprocess
import termios
from pathlib import Path

master, slave = pty.openpty()
try:
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 960, 640))

    def attach():
        os.setsid()
        fcntl.ioctl(0, termios.TIOCSCTTY, 0)

    cmd = ['nvim', '-n', '--headless', '-u', 'NONE', '-i', 'NONE', '-l', str(Path(__file__).with_name('tty.lua'))]
    for label, stdin, setup in [('controlling tty', slave, attach), ('detached with tty stdin', slave, os.setsid)]:
        result = subprocess.run(cmd, stdin=stdin, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                preexec_fn=setup, timeout=10, text=True)
        print(label + ': ' + result.stdout + result.stderr, end='')
        assert result.returncode == 0
        assert os.read(master, 100) == b'PROBE_WRITE'
    saved = os.dup(0)
    try:
        os.dup2(slave, 0)
        result = subprocess.run(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True, timeout=10, text=True)
    finally:
        os.dup2(saved, 0)
        os.close(saved)
    print('detached server with TUI parent tty: ' + result.stdout + result.stderr, end='')
    assert result.returncode == 0
    assert os.read(master, 100) == b'PROBE_WRITE'
finally:
    os.close(slave)
    os.close(master)
