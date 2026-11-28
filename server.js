// 훈련장 1v1 웹서버 + 게임 방 중계 — 추가 설치 없이 Node.js 기본 기능만 사용
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
  // 로그인 도구 (학교 등에서 구글 서버가 막혀도 로그인되게 우리 서버에서 줘요)
  '/firebase/firebase-app-compat.js': 'firebase/firebase-app-compat.js',
  '/firebase/firebase-auth-compat.js': 'firebase/firebase-auth-compat.js',
};

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
};

const server = http.createServer((req, res) => {
  let pathname;
  try {
    pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
  } catch {
    res.writeHead(400).end('Bad Request');
    return;
  }

  const file = ROUTES[pathname];
  if (!file || (req.method !== 'GET' && req.method !== 'HEAD')) {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }).end('페이지를 찾을 수 없어요');
    return;
  }

  fs.readFile(path.join(ROOT, file), (err, data) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'text/plain; charset=utf-8' }).end('파일을 읽지 못했어요');
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

// ---- 게임 방 중계 (웹소켓) : wss://주소/room/<방 이름> 에 붙은 사람끼리 메시지를 그대로 전달해요 ----
// 추가 설치 없이 Node 기본 기능으로 웹소켓을 직접 처리해요 (글자 메시지만)
const crypto = require('crypto');
const ROOMS = new Map(); // 방 이름 → 접속한 소켓들
function wsSend(sock, str) {
  const data = Buffer.from(str, 'utf8'), n = data.length;
  let head;
  if (n < 126) head = Buffer.from([0x81, n]);
  else if (n < 65536) { head = Buffer.alloc(4); head[0] = 0x81; head[1] = 126; head.writeUInt16BE(n, 2); }
  else { head = Buffer.alloc(10); head[0] = 0x81; head[1] = 127; head.writeBigUInt64BE(BigInt(n), 2); }
  try { sock.write(Buffer.concat([head, data])); } catch {}
}
function wsCtrl(sock, op, payload = Buffer.alloc(0)) { try { sock.write(Buffer.concat([Buffer.from([0x80 | op, payload.length]), payload])); } catch {} }
server.on('upgrade', (req, sock) => {
  let name;
  try { name = decodeURIComponent(new URL(req.url, 'http://localhost').pathname).match(/^\/room\/([A-Za-z0-9_\/.-]{1,64})$/)?.[1]; } catch {}
  const key = req.headers['sec-websocket-key'];
  if (!name || !key || (req.headers.upgrade || '').toLowerCase() !== 'websocket') { sock.end('HTTP/1.1 400 Bad Request\r\n\r\n'); return; }
  const room = ROOMS.get(name) || new Set();
  if (room.size >= 16) { sock.end('HTTP/1.1 429 Too Many Requests\r\n\r\n'); return; }
  const accept = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  sock.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + accept + '\r\n\r\n');
  sock.setNoDelay(true); sock.setKeepAlive(true, 20000);
  room.add(sock); ROOMS.set(name, room);
  let buf = Buffer.alloc(0), frag = [];
  const bye = () => { room.delete(sock); if (!room.size) ROOMS.delete(name); try { sock.destroy(); } catch {} };
  sock.on('close', bye); sock.on('error', bye);
  sock.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    if (buf.length > 1 << 20) { bye(); return; }
    while (buf.length >= 2) {
      const fin = buf[0] & 0x80, op = buf[0] & 0x0f, masked = buf[1] & 0x80;
      let len = buf[1] & 0x7f, off = 2;
      if (len === 126) { if (buf.length < 4) return; len = buf.readUInt16BE(2); off = 4; }
      else if (len === 127) { if (buf.length < 10) return; len = Number(buf.readBigUInt64BE(2)); off = 10; }
      if (len > 65536) { bye(); return; }
      const need = off + (masked ? 4 : 0) + len; if (buf.length < need) return;
      let data = buf.subarray(off + (masked ? 4 : 0), need);
      if (masked) { const m = buf.subarray(off, off + 4); data = Buffer.from(data); for (let i = 0; i < data.length; i++) data[i] ^= m[i & 3]; }
      buf = buf.subarray(need);
      if (op === 8) { wsCtrl(sock, 8); bye(); return; }
      if (op === 9) { wsCtrl(sock, 10, data); continue; }
      if (op === 10) continue;
      if (op === 1 || op === 0) {
        frag.push(data); if (!fin) continue;
        const msg = Buffer.concat(frag).toString('utf8'); frag = [];
        for (const o of room) if (o !== sock) wsSend(o, msg);
      }
    }
  });
});
// 무료 서버가 잠들지 않게 접속한 사람에게 가끔 핑 (연결 유지)
setInterval(() => { for (const room of ROOMS.values()) for (const s of room) wsCtrl(s, 9); }, 25000);

server.listen(PORT, () => {
  console.log(`훈련장 1v1 실행 중: http://localhost:${PORT}`);
});
