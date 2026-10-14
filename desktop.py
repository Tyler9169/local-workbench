"""Entry point for the bundled desktop backend."""
import fcntl
import json
import os
import sys
import webbrowser
from pathlib import Path
import server


def main():
    server.DATA.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock = open(server.DATA / 'desktop.lock', 'a')
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        raise SystemExit('工作台已经运行。')
    http = None
    for port in range(43140, 43150):
        try:
            http = server.ThreadingHTTPServer(('127.0.0.1', port), server.Handler)
            break
        except OSError:
            continue
    if http is None:
        raise SystemExit('工作台端口不可用。')
    http.daemon_threads = True
    url = f'http://127.0.0.1:{http.server_port}'
    state = server.DATA / 'desktop.json'
    state.write_text(json.dumps({'url': url, 'pid': os.getpid()}))
    state.chmod(0o600)
    print(url, flush=True)
    if '--no-open' not in sys.argv:
        webbrowser.open(url)
    try:
        http.serve_forever()
    finally:
        http.server_close()


if __name__ == '__main__':
    main()
