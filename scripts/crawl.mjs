#!/usr/bin/env node
// 自動爬網站地圖 → assistant/public/data/sitemap.json
//   node --experimental-websocket scripts/crawl.mjs [--port 5180] [--fresh] [--out <檔案>]
// 需要先建置 TownPass-Services 與 assistant；本機伺服器沒開會自動啟動。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const arg = (k, d) => { const i = process.argv.indexOf(`--${k}`); return i < 0 ? d : process.argv[i + 1] ?? true; };
const port = Number(arg('port', 5180));
const fresh = process.argv.includes('--fresh');
const sitemap = path.join(root, 'assistant/public/data/sitemap.json');
const out = path.resolve(arg('out', sitemap));
const base = `http://127.0.0.1:${port}`;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function up(url) { try { return (await fetch(url)).ok; } catch { return false; } }

function findChrome() {
  const list = [process.env.CHROME,
    'C:/Program Files/Google/Chrome/Application/chrome.exe', 'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
    'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', '/usr/bin/google-chrome', '/usr/bin/chromium', '/usr/bin/chromium-browser'];
  const c = list.find((p) => p && fs.existsSync(p));
  if (!c) throw new Error('找不到 Chrome，請用 CHROME 環境變數指定');
  return c;
}

const children = [];
if (!(await up(`${base}/assistant/`))) {
  children.push(spawn(process.execPath, [path.join(root, 'scripts/serve-local.mjs'), '--port', String(port), '--host', '127.0.0.1'], { stdio: 'ignore' }));
  for (let i = 0; i < 50 && !(await up(`${base}/assistant/`)); i++) await sleep(200);
}

const debugPort = 9333;
const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'crawl-'));
children.push(spawn(findChrome(), ['--headless=new', '--disable-gpu', `--remote-debugging-port=${debugPort}`, `--user-data-dir=${profile}`, '--window-size=412,900', 'about:blank'], { stdio: 'ignore' }));
let target;
for (let i = 0; i < 50 && !target; i++) {
  await sleep(200);
  try { target = (await (await fetch(`http://127.0.0.1:${debugPort}/json/list`)).json()).find((t) => t.type === 'page'); } catch {}
}
if (!target) throw new Error('Chrome 沒有啟動');

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((r) => ws.addEventListener('open', r, { once: true }));
let seq = 0;
const pending = new Map();
ws.addEventListener('message', (e) => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } });
const send = (method, params = {}) => new Promise((r) => { const id = ++seq; pending.set(id, r); ws.send(JSON.stringify({ id, method, params })); });
const run = async (expr) => {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true });
  if (r.result?.exceptionDetails) throw new Error(r.result.exceptionDetails.exception?.description || 'evaluate failed');
  return r.result?.result?.value;
};

await send('Page.navigate', { url: `${base}/assistant/` });
await sleep(2500);
await run(fs.readFileSync(path.join(root, 'tools/crawl/crawler.js'), 'utf8'));
const seeds = fs.existsSync(sitemap) && !fresh ? Object.keys(JSON.parse(fs.readFileSync(sitemap, 'utf8')).pages) : ['/'];
await run('__crawl.reset()');

const t0 = Date.now();
const queue = [...seeds];
const done = new Set();
while (queue.length) {
  const u = queue.shift();
  if (done.has(u)) continue;
  const r = await run(`__crawl.scanFully(${JSON.stringify(u)})`);
  done.add(u);
  console.log(`${String(done.size).padStart(3)}  ${u}  ${r.total} 個元素  ${Math.round((Date.now() - t0) / 1000)} s`);
  if (!queue.length) { const n = await run('__crawl.next()'); if (n) queue.push(n); }
}
fs.writeFileSync(out, await run('__crawl.dump()'));
console.log(`寫入 ${path.relative(root, out)}：${done.size} 頁`);
ws.close();
for (const c of children) c.kill();
