#!/usr/bin/env python3
"""fernedda — navigate your filesystem through pictures.

Run:  python3 server.py [--no-browser]
Then open http://127.0.0.1:8765
"""
import hashlib
import json
import mimetypes
import os
import re
import shlex
import shutil
import subprocess
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).resolve().parent
DATA = HERE / "data"
IMAGES = DATA / "images"
MAPS = DATA / "maps.json"
PORT = int(os.environ.get("FERNEDDA_PORT", 8765))
ALLOWED_HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}
MAX_IMAGE = 64 * 1024 * 1024
IMG_ID = re.compile(r"^[0-9a-f]{16,64}\.[a-z0-9]{1,5}$")

IMAGES.mkdir(parents=True, exist_ok=True)
lock = threading.Lock()


def load_maps():
    try:
        return json.loads(MAPS.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_maps(maps):
    tmp = MAPS.with_suffix(".tmp")
    tmp.write_text(json.dumps(maps, indent=1))
    tmp.replace(MAPS)


def resolve(p):
    return os.path.realpath(os.path.expanduser(p or "~"))


def list_dir(path):
    out = []
    with os.scandir(path) as it:
        for e in it:
            if e.name.startswith("."):
                continue
            try:
                is_dir = e.is_dir()
            except OSError:
                is_dir = False
            out.append({"name": e.name, "dir": is_dir})
    out.sort(key=lambda x: (not x["dir"], x["name"].lower()))
    return out


# Text/code files open in a terminal editor; everything else goes to the system default app.
EDITOR = os.environ.get("FERNEDDA_EDITOR", "nvim")
# How to run a command in a new terminal window. Override with e.g. FERNEDDA_TERMINAL="kitty".
TERMINALS = {
    "alacritty": ["alacritty", "-e"],
    "kitty": ["kitty"],
    "foot": ["foot"],
    "wezterm": ["wezterm", "start", "--"],
    "ghostty": ["ghostty", "-e"],
    "ptyxis": ["ptyxis", "--new-window", "--"],
    "gnome-terminal": ["gnome-terminal", "--"],
    "konsole": ["konsole", "-e"],
    "xterm": ["xterm", "-e"],
}
# Extensions that are always text, including ones mimetypes gets wrong (.ts -> video/mp2t).
TEXT_EXTS = {
    "txt", "md", "markdown", "rst", "org", "log", "csv", "tsv",
    "py", "js", "mjs", "cjs", "ts", "tsx", "jsx", "json", "jsonc", "yaml", "yml", "toml", "ini", "cfg", "conf",
    "env", "xml", "html", "htm", "css", "scss", "sass", "less", "vue", "svelte",
    "c", "h", "cpp", "cc", "hpp", "cs", "java", "kt", "kts", "go", "rs", "rb", "php", "pl", "lua", "vim",
    "sh", "bash", "zsh", "fish", "ps1", "bat", "sql", "graphql", "proto", "swift", "dart", "scala", "clj",
    "ex", "exs", "erl", "hs", "ml", "nix", "zig", "r", "jl", "tex", "bib", "diff", "patch", "gitignore",
    "dockerfile", "makefile", "cmake", "gradle", "lock", "svg",
}
TEXT_MIMES = {"application/json", "application/xml", "application/javascript", "application/x-sh",
              "application/toml", "application/x-yaml", "image/svg+xml"}


def terminal_cmd():
    env = os.environ.get("FERNEDDA_TERMINAL")
    if env:
        return shlex.split(env)
    for name, cmd in TERMINALS.items():
        if shutil.which(name):
            return cmd
    return None


def is_text(path):
    name = os.path.basename(path).lower()
    ext = name.rsplit(".", 1)[-1] if "." in name else name
    if ext in TEXT_EXTS:
        return True
    mime = mimetypes.guess_type(path)[0]
    if mime:
        return mime.startswith("text/") or mime in TEXT_MIMES
    # Unknown type: sniff it. No NUL bytes and valid UTF-8 means text.
    try:
        with open(path, "rb") as f:
            chunk = f.read(8192)
    except OSError:
        return False
    if b"\0" in chunk:
        return False
    try:
        chunk.decode("utf-8")
    except UnicodeDecodeError as e:
        return e.start >= len(chunk) - 3  # only a multibyte char cut off at the chunk boundary
    return True


def open_file(path):
    """Open path and return a short name of what it was opened with."""
    if os.path.isfile(path) and is_text(path):
        term = terminal_cmd()
        if term and shutil.which(EDITOR):
            subprocess.Popen(term + [EDITOR, path], cwd=os.path.dirname(path),
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            return EDITOR
    if sys.platform == "darwin":
        cmd = ["open", path]
    elif sys.platform == "win32":
        os.startfile(path)  # noqa
        return "default app"
    else:
        cmd = ["xdg-open", path]
    subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    return "default app"


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="application/json", headers=None):
        if not isinstance(body, (bytes, bytearray)):
            body = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def err(self, code, msg):
        self.send(code, {"error": msg})

    def guard(self):
        # Only talk to pages served from ourselves (blocks DNS rebinding / cross-site requests).
        if self.headers.get("Host") not in ALLOWED_HOSTS:
            self.err(403, "bad host")
            return False
        origin = self.headers.get("Origin")
        if self.command == "POST" and origin and origin.split("//", 1)[-1] not in ALLOWED_HOSTS:
            self.err(403, "bad origin")
            return False
        return True

    def read_json(self):
        if self.headers.get("Content-Type", "").split(";")[0] != "application/json":
            raise ValueError("expected JSON")
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}")

    # ---------- GET ----------
    def do_GET(self):
        if not self.guard():
            return
        url = urlparse(self.path)
        q = parse_qs(url.query)

        if url.path == "/":
            return self.send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8",
                             {"Cache-Control": "no-cache"})

        if url.path == "/api/dir":
            path = resolve(q.get("path", [""])[0])
            if not os.path.isdir(path):
                return self.err(404, f"Not a folder: {path}")
            try:
                entries = list_dir(path)
            except PermissionError:
                return self.err(403, f"Permission denied: {path}")
            with lock:
                m = load_maps().get(path, {})
            parent = os.path.dirname(path)
            return self.send(200, {
                "path": path,
                "parent": parent if parent != path else None,
                "entries": entries,
                "map": {"image": m.get("image"), "hotspots": m.get("hotspots", [])},
            })

        if url.path.startswith("/api/img/"):
            name = url.path.rsplit("/", 1)[-1]
            f = IMAGES / name
            if not IMG_ID.match(name) or not f.is_file():
                return self.err(404, "no image")
            ctype = mimetypes.guess_type(name)[0] or "application/octet-stream"
            # Content-addressed, so it can be cached forever.
            return self.send(200, f.read_bytes(), ctype,
                             {"Cache-Control": "public, max-age=31536000, immutable"})

        self.err(404, "not found")

    # ---------- POST ----------
    def do_POST(self):
        if not self.guard():
            return
        url = urlparse(self.path)
        q = parse_qs(url.query)
        try:
            if url.path == "/api/map":
                body = self.read_json()
                path = resolve(body["path"])
                hotspots = [
                    {k: (float(h[k]) if k != "target" else str(h[k])) for k in ("x", "y", "w", "h", "target")}
                    for h in body["hotspots"]
                ]
                with lock:
                    maps = load_maps()
                    maps.setdefault(path, {})["hotspots"] = hotspots
                    save_maps(maps)
                return self.send(200, {"ok": True})

            if url.path == "/api/image":
                path = resolve(q.get("path", [""])[0])
                ctype = self.headers.get("Content-Type", "")
                if not ctype.startswith("image/"):
                    return self.err(400, "expected an image")
                n = int(self.headers.get("Content-Length") or 0)
                if n > MAX_IMAGE:
                    return self.err(413, "image too large")
                data = self.rfile.read(n)
                ext = (mimetypes.guess_extension(ctype) or ".img").lstrip(".")
                name = f"{hashlib.sha256(data).hexdigest()[:32]}.{ext}"
                (IMAGES / name).write_bytes(data)
                with lock:
                    maps = load_maps()
                    maps.setdefault(path, {})["image"] = name
                    save_maps(maps)
                return self.send(200, {"image": name})

            if url.path == "/api/open":
                path = resolve(self.read_json()["path"])
                if not os.path.exists(path):
                    return self.err(404, f"Missing: {path}")
                return self.send(200, {"with": open_file(path)})
        except (ValueError, KeyError, TypeError) as e:
            return self.err(400, str(e))
        self.err(404, "not found")


def main():
    srv = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    url = f"http://127.0.0.1:{PORT}"
    print(f"fernedda running at {url}  (Ctrl+C to stop)")
    if "--no-browser" not in sys.argv:
        threading.Timer(0.3, webbrowser.open, [url]).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
