import { fileURLToPath, URL } from 'node:url';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { defineConfig } from 'vite';

// 除錯面板顯示的版本戳：用 src/ 的內容雜湊，不用編譯時間。
// guide-overlay.js 有進 git（TownPass/assets/js/），用時間的話每次重編都會改到它，build-info.json 永遠是 +dirty。
function sourceStamp(dir: string): string {
  const h = createHash('sha1');
  const walk = (d: string) => {
    for (const name of fs.readdirSync(d).sort()) {
      const p = path.join(d, name);
      if (fs.statSync(p).isDirectory()) walk(p);
      else {
        h.update(path.relative(dir, p).split(path.sep).join('/'));
        h.update(fs.readFileSync(p));
      }
    }
  };
  walk(dir);
  return 'src ' + h.digest('hex').slice(0, 8);
}

// 引導層：打包成單一 IIFE 檔 dist/guide-overlay.js，
// 由 nginx / serve-local 注入到服務頁，或由 TownPass 用 initialUserScripts 注入。
export default defineConfig({
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) }
  },
  define: {
    // overlay 不在 vite app 裡，import.meta.env.BASE_URL 用不到；catalog.ts 會退回 window 設定
    'import.meta.env.BASE_URL': JSON.stringify('/assistant/'),
    'import.meta.env.VITE_LLM_URL': JSON.stringify(process.env.VITE_LLM_URL ?? ''),
    __OVERLAY_BUILD__: JSON.stringify(sourceStamp(fileURLToPath(new URL('./src', import.meta.url))))
  },
  build: {
    target: 'es2018',
    outDir: 'dist',
    emptyOutDir: false,
    minify: true,
    lib: {
      entry: fileURLToPath(new URL('./src/overlay/index.ts', import.meta.url)),
      name: 'TPGuide',
      formats: ['iife'],
      fileName: () => 'guide-overlay.js'
    },
    rollupOptions: { output: { inlineDynamicImports: true } }
  }
});
