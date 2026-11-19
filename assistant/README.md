# 小幫手網頁 assistant/

Polaris 台北通小幫手的網頁本體：語意導航畫面與注入到服務頁的陪伴引導層。專案總覽見根目錄的 `README.md`，資料重建、重訓與遷移步驟見 `docs/MAINTENANCE.md`。

## 目錄

| 路徑 | 內容 |
|---|---|
| `src/ui/` | 主畫面 `AssistantHome.vue`、評測頁、開發者儀表板 |
| `src/core/` | 決策規則 `decide.ts`、prompt 組裝 `prompt.ts`、工具表 `registry.ts`、查表融合 `fuse.ts`、固定指令 `rules.ts`、參數抽取 `extract.ts`、原生橋接 `bridge.ts` |
| `src/engines/` | 決策引擎：`llm.ts` 呼叫 llama-server，`cls.ts` 為 e5 分類器，`tiny.ts` 為 n-gram 分類器，`embed.ts` 為零樣本對照組 |
| `src/overlay/` | 陪伴引導層，建置為 `guide-overlay.js` |
| `src/eval/` | 評測邏輯，瀏覽器與 Node 共用 |
| `public/data/` | 服務目錄 `catalog.json`、工具表 `registry.json`、網站地圖 `sitemap.json`、五種語言介面文字 `copy.*.json`、測試集 |
| `public/guides/` | 31 份導覽腳本 |
| `public/models/` | e5 分類器 `cls-services/`、n-gram 分類器 `tinycls.*.json` |
| `scripts/` | 匯出 prompt、複製引導層到 App、下載與預算零樣本向量 |

## 建置與執行

```bash
pnpm install
pnpm build-only          # 主畫面、引導層，並把 guide-overlay.js 複製到 TownPass/assets/js/
cd .. && node scripts/serve-local.mjs --port 5180
```

開啟 `http://localhost:5180/assistant/`。網址參數：`?engine=auto|llm|cls|tiny|embed` 指定引擎，`?llm=<網址>` 指定 llama-server，`?lang=zh|en|vi|id|th` 指定語言，`?q=<句子>` 直接判斷一句。

## 決策引擎

所有引擎都實作同一個介面：輸入句子，輸出每個工具代號的機率分布。之後的查表融合與決策規則由 `src/core/` 共用。

| 引擎 | 模型 | 大小與延遲 | 1,027 句測試集：第一輪、兩輪內、範圍外辨識 |
|---|---|---|---|
| `llm` | Gemma 3 270M 微調為單一 token 決策器，GGUF Q8_0 | 292 MB，筆電 GPU 45 ms，手機 NPU 63 ms | 93.4%、97.4%、99.2% |
| `cls` | multilingual-e5-small 微調分類器，ONNX int8 | 27.5 MB，6 ms | 94.9%、96.8%、90.6% |
| `tiny` | 字元 n-gram 分類器 | 2 MB，1 ms 以內 | 72.5%、84.9%、95.3% |
| `embed` | e5-small 零樣本相似度，僅供對照 | 118 MB，6 ms | 舊版 1,052 句：50.4%、63.7%、49.2% |

延遲為筆電量測，手機 NPU 的數字見 `eval/PHONE.md`。

`auto` 的順序：App 內的 llama-server、設定的 LLM 網址、`cls`、`tiny`、`embed`，使用第一個可用的引擎。

## 導覽腳本格式

`public/guides/<id>.json` 的每一步包含：`url` 所在頁面、`find` 依序嘗試的定位方式（text、label、role、css）、`say` 與 `more` 說明文字、`done_when` 完成條件（click、input、route、manual）、`accept` 參數格式（digits、phone、date）、`confirm` 長輩模式是否多確認一次。`{{entity}}` 與 `{{keyword}}` 由工具表在執行時帶入。

## 原生橋接

`stt`、`lang_id`、`translate`、`translate_prepare`、`tts` 五個訊息，實作在 `TownPass/lib/util/web_message_handler/tp_assistant_message_handler.dart`。一般瀏覽器沒有橋接時，改用 Web Speech API 與簡單的語言判斷，方便在電腦上開發。
