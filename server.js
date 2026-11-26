// 훈련장 1v1 웹서버 — 추가 설치 없이 Node.js 기본 기능만 사용
const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.PORT) || 3000;
const ROOT = __dirname;
const GAME_FILE = '훈련장 1v1.html';

// 웹에서 열 수 있는 파일만 허용 (server.js, package.json 등은 노출 안 함)
const ROUTES = {
  '/': GAME_FILE,
  '/index.html': GAME_FILE,
  ['/' + GAME_FILE]: GAME_FILE,
  '/version.json': 'version.json',
};

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.wasm': 'application/wasm',
  '.pck': 'application/octet-stream',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

// Godot 버전 (웹으로 내보낸 것): /godot/ 아래 web/godot 폴더의 파일만 보여줘요
const GODOT_DIR = path.join(ROOT, 'web', 'godot');
function godotFile(pathname) {
  if (pathname === '/godot') return null;
  if (!pathname.startsWith('/godot/')) return null;
  const rel = pathname.slice('/godot/'.length) || 'index.html';
  const full = path.normalize(path.join(GODOT_DIR, rel));
  if (!full.startsWith(GODOT_DIR + path.sep)) return null; // 폴더 밖으로 못 나가게
  return path.relative(ROOT, full);
}

const server = http.createServer((req, res) => {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch {
    res.writeHead(400).end('Bad Request');
    return;
  }

  if (pathname === '/godot') {
    res.writeHead(301, { Location: '/godot/' }).end();
    return;
  }
  const file = ROUTES[pathname] || godotFile(pathname);
  if (!file || (req.method !== 'GET' && req.method !== 'HEAD')) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('페이지를 찾을 수 없어요');
    return;
  }

  fs.readFile(path.join(ROOT, file), (err, data) => {
    if (err) {
      const nf = err.code === 'ENOENT' || err.code === 'EISDIR';
      res.writeHead(nf ? 404 : 500, { 'Content-Type': 'text/plain; charset=utf-8' }).end(nf ? '페이지를 찾을 수 없어요' : '파일을 읽지 못했어요');
      return;
    }
    res.writeHead(200, {
      'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream',
      'Content-Length': data.length,
      'Cache-Control': 'no-cache',
    });
    res.end(req.method === 'HEAD' ? undefined : data);
  });
});

server.listen(PORT, () => {
  console.log(`훈련장 1v1 실행 중: http://localhost:${PORT}`);
});
