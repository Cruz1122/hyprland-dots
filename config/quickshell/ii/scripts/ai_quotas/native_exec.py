"""Give the owned official-client process its PTY as a controlling terminal."""
import fcntl
import os
import sys
import termios

if __name__ == "__main__":
    if len(sys.argv) < 2 or not os.isatty(0):
        raise SystemExit(1)
    # Popen(start_new_session=True) made this single-threaded shim the session leader.
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
    os.execvpe(sys.argv[1], sys.argv[1:], os.environ)
