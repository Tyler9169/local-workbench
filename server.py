"""Local Workbench: standard-library-only, loopback-only tool launcher."""
import argparse
import json
import os
import re
import subprocess
import sys
import threading
import time
import uuid
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parent
DATA = Path(os.environ.get('WORKBENCH_DATA_DIR', str(ROOT / 'data'))).expanduser().resolve()
LOCK = threading.RLock()
CATEGORIES = ('日常工具', '影音创作', '开发分析', '资讯灵感')


def validate(entry):
    fields = {'id', 'name', 'category', 'type', 'target', 'description'}
    if not isinstance(entry, dict) or set(entry) != fields or not all(isinstance(v, str) for v in entry.values()):
        raise ValueError('工具字段不完整或格式不正确。')
    e = {k: v.strip() for k, v in entry.items()}
    if not re.fullmatch(r'[a-z0-9-]{1,64}', e['id']):
        raise ValueError('工具编号不正确。')
    if not 1 <= len(e['name']) <= 40 or len(e['description']) > 200:
        raise ValueError('名称需为 1–40 字，说明最多 200 字。')
    if e['category'] not in CATEGORIES or e['type'] not in ('app', 'folder', 'url'):
        raise ValueError('请选择有效的分类和类型。')
    target = e['target']
    if not target or len(target) > 2048 or any(ord(c) < 32 for c in target):
        raise ValueError('请填写有效的地址或路径。')
    if e['type'] == 'url':
        u = urlsplit(target)
        if not u.hostname or u.username or u.password or u.query or u.fragment:
            raise ValueError('网址不能包含账号密码、查询参数或片段。')
        if u.scheme != 'https' and not (u.scheme == 'http' and u.hostname in ('localhost', '127.0.0.1', '::1')):
            raise ValueError('使用 HTTPS 网址，或本机 HTTP 服务地址。')
        _ = u.port
    else:
        p = Path(target).expanduser()
        if not p.is_absolute():
            raise ValueError('请输入绝对路径，也可以使用 ~/。')
        # Missing destinations are retained so a disconnected disk does not erase the catalog.
        if p.exists() and not p.is_dir():
            raise ValueError('仅支持目录或 macOS .app 应用包，不接受脚本和可执行文件。')
        if e['type'] == 'app' and (sys.platform != 'darwin' or p.suffix != '.app'):
            raise ValueError('应用入口仅支持 macOS 的 .app 应用包。')
        e['target'] = str(p.resolve())
    return e


def load():
    file = DATA / 'tools.json'
    if not file.exists():
        return []
    items = json.loads(file.read_text(encoding='utf-8'))
    if not isinstance(items, list) or len(items) > 200:
        raise ValueError('配置必须是最多 200 项的列表。')
    result = [validate(e) for e in items]
    if len({e['id'] for e in result}) != len(result):
        raise ValueError('配置中有重复编号。')
    return result


def save(items):
    DATA.mkdir(parents=True, exist_ok=True, mode=0o700)
    file = DATA / 'tools.json'
    temp = DATA / 'tools.tmp'
    temp.write_text(json.dumps(items, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temp.chmod(0o600)
    temp.replace(file)


def present(e):
    is_url = e['type'] == 'url'
    available = is_url or Path(e['target']).is_dir()
    return {**e, 'subtitle': 'MY TOOL', 'extra': True,
            'kind': {'app': '桌面应用', 'folder': '项目目录', 'url': '在线网页'}[e['type']],
            'icon': {'app': 'layers', 'folder': 'code', 'url': 'grid'}[e['type']],
            'path': '' if is_url else e['target'], 'url': e['target'] if is_url else '',
            'note': '本地服务链接需要对应服务已经启动。' if is_url else '打开原位置，不复制或移动文件。',
            'available': available, 'state': 'web' if is_url else ('installed' if available else 'missing'),
            'status': '网页入口 · 未探测' if is_url else ('位置可用' if available else '位置未找到 · 请编辑')}


def open_target(e, action):
    e = validate(e)
    if e['type'] == 'url':
        if action != 'open':
            raise ValueError('网页没有本地目录。')
        if not webbrowser.open(e['target']):
            raise ValueError('未找到默认浏览器，请检查系统设置。')
        return
    p = Path(e['target'])
    if not p.is_dir():
        raise ValueError('位置不存在，请编辑入口路径。')
    if action == 'folder' and e['type'] == 'app':
        p = p.parent
    if sys.platform == 'darwin':
        subprocess.run(['/usr/bin/open', str(p)], check=True, timeout=10)
    elif sys.platform == 'win32':
        os.startfile(str(p))
    else:
        subprocess.run(['xdg-open', str(p)], check=True, timeout=10)


class Handler(BaseHTTPRequestHandler):
    server_version = 'LocalWorkbench/2.0'

    def log_message(self, *args):
        pass

    def send(self, code, data, mime='application/json; charset=utf-8'):
        body = json.dumps(data, ensure_ascii=False).encode() if isinstance(data, (dict, list)) else data
        self.send_response(code)
        for key, value in {'Content-Type': mime, 'Content-Length': str(len(body)), 'Cache-Control': 'no-store',
                           'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer',
                           'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"}.items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body)

    def host_ok(self):
        return self.headers.get('Host') in (f'127.0.0.1:{self.server.server_port}', f'localhost:{self.server.server_port}')

    def do_GET(self):
        if not self.host_ok():
            return self.send(403, {'error': '不允许的主机。'})
        if self.path == '/api/health':
            return self.send(200, {'app': 'local-workbench', 'version': '2.0.0'})
        if self.path == '/api/tools':
            try:
                with LOCK:
                    items = load()
                return self.send(200, {'tools': [present(e) for e in items], 'checkedAt': time.strftime('%H:%M:%S')})
            except (ValueError, OSError):
                return self.send(500, {'error': '工具配置无法读取，请检查 data/tools.json；原文件没有被覆盖。'})
        files = {'/': ('index.html', 'text/html'), '/app.js': ('app.js', 'text/javascript'),
                 '/style.css': ('style.css', 'text/css'), '/favicon.svg': ('favicon.svg', 'image/svg+xml')}
        if self.path not in files:
            return self.send(404, {'error': '未找到。'})
        name, mime = files[self.path]
        self.send(200, (ROOT / 'dist' / name).read_bytes(), mime + '; charset=utf-8')

    def do_POST(self):
        if (not self.host_ok() or self.headers.get('Origin') != f'http://{self.headers.get("Host")}'
                or self.headers.get('X-Workbench') != '1'):
            return self.send(403, {'error': '请从本机工作台执行操作。'})
        if self.path not in ('/api/tools', '/api/delete', '/api/action'):
            return self.send(404, {'error': '未找到。'})
        if self.headers.get('Content-Type') != 'application/json':
            return self.send(415, {'error': '需要 JSON 请求。'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 16384:
                return self.send(413, {'error': '请求长度不允许。'})
            body = json.loads(self.rfile.read(length))
            if not isinstance(body, dict):
                raise ValueError('请求格式错误。')
            with LOCK:
                items = load()
                if self.path == '/api/tools':
                    entry = validate(body)
                    if any(x['target'] == entry['target'] and x['id'] != entry['id'] for x in items):
                        raise ValueError('这个地址已经添加过了。')
                    items = [entry if x['id'] == entry['id'] else x for x in items] if any(x['id'] == entry['id'] for x in items) else [*items, entry]
                    if len(items) > 200:
                        raise ValueError('最多支持 200 个入口。')
                    save(items)
                    return self.send(200, {'message': '入口已保存。'})
                allowed = {'id'} if self.path == '/api/delete' else {'id', 'action'}
                if set(body) != allowed or not all(isinstance(v, str) for v in body.values()):
                    raise ValueError('请求格式错误。')
                entry = next((x for x in items if x['id'] == body['id']), None)
                if not entry:
                    return self.send(404, {'error': '工具不存在，请刷新。'})
                if self.path == '/api/delete':
                    save([x for x in items if x['id'] != entry['id']])
                    return self.send(200, {'message': '入口已移除，原应用和文件保留。'})
                if body['action'] not in ('open', 'folder'):
                    raise ValueError('未允许的操作。')
            open_target(entry, body['action'])
            self.send(200, {'message': '系统已接受打开请求。'})
        except (ValueError, TypeError) as exc:
            self.send(400, {'error': str(exc)})
        except (OSError, subprocess.SubprocessError):
            self.send(500, {'error': '操作未完成，请检查目录权限和系统打开程序。'})


def main():
    parser = argparse.ArgumentParser(description='本地工作台：仅在本机运行的工具入口')
    parser.add_argument('--port', type=int, default=43120)
    parser.add_argument('--no-open', action='store_true', help='不自动打开浏览器')
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error('端口范围：1024–65535')
    try:
        http = ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    except OSError:
        parser.exit(1, f'端口 {args.port} 不可用，请用 --port 指定其他端口。\n')
    http.daemon_threads = True
    url = f'http://127.0.0.1:{args.port}'
    print(f'本地工作台：{url}\n配置目录：{DATA}\n按 Ctrl+C 停止工作台。', flush=True)
    if not args.no_open:
        webbrowser.open(url)
    try:
        http.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        http.server_close()


if __name__ == '__main__':
    main()
