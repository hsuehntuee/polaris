# 維護手冊：遷移、重生資料、重訓權重

這份文件寫給接手維護 Polaris 台北通小幫手的人。依照你修改的內容找到對應章節，照順序執行指令即可。移植到其他平台見 [PORTING.md](PORTING.md)。
所有指令都在 repo 根目錄執行，除非另外註明。Windows 用 PowerShell；`.sh` 腳本用 Git Bash。

- [0. 快速指令](#0-快速指令)
- [1. 專案裡有什麼、不在 git 裡的是什麼](#1-專案裡有什麼不在-git-裡的是什麼)
- [2. 遷移到新電腦](#2-遷移到新電腦)
- [3. 重生資料](#3-重生資料)
- [4. 重訓權重](#4-重訓權重)
- [5. 評測](#5-評測)
- [6. 打包與發布](#6-打包與發布)
- [7. 新增一個服務](#7-新增一個服務)
- [8. 常見問題](#8-常見問題)

---

## 0. 快速指令

從 repo 根目錄依序執行。每一段都可以單獨跑，細節在後面的章節。

**安裝依賴**

```powershell
pnpm -C TownPass-Services install; pnpm -C assistant install
pip install -r tools/requirements.txt
```

**開啟服務**

```powershell
pnpm -C TownPass-Services build-only; pnpm -C assistant build-only
node scripts/serve-local.mjs --port 5180
```

開啟 `http://localhost:5180/assistant/`。

**爬網站地圖**

```powershell
node --experimental-websocket scripts/crawl.mjs
```

本機伺服器沒開會自動啟動，結果寫入 `assistant/public/data/sitemap.json`。加 `--fresh` 從首頁重新探索。

**產生訓練資料**

```powershell
python -I tools/tinycls/mine_mock.py
python -I tools/registry/build_registry.py
python -I tools/llm/gen_ui_data.py
python -I tools/tinycls/gen_more_data.py
```

依序是：從服務頁擷取句子與項目名稱、重建工具表、由網站地圖產生按鈕選擇題、把核心說法與開頭、結尾、情境、語音錯字交叉組合成訓練句。

**訓練兩個分類頭**

```powershell
python -I tools/tinycls/train.py --set services --eval
python -I tools/tinycls/train.py --set commands
python -I tools/encoder/train_cls.py --eval
```

n-gram 分類頭只要 numpy，幾秒完成；e5 分類頭建議用 GPU。輸出直接寫進 `assistant/public/models/`。

**重訓 Gemma 決策器**

```powershell
pnpm -C assistant exec tsx scripts/dump-prompts.ts
python -I tools/llm/finetune_gemma.py
```

需要 CUDA GPU，輸出 `tools/llm/out/gemma-3-270m-decider-Q8_0.gguf`。

**評測**

```powershell
pnpm -C assistant eval --engine cls --fuse --testset ../assistant/public/data/testset_1k.json --foreign
```

**打包進 App**

```powershell
pnpm -C TownPass-Services build-only; pnpm -C assistant build-only
node scripts/bundle-web.mjs
node scripts/prepare-llama-jni.mjs
```

網頁與兩個分類頭進 `TownPass/assets/web/`，決策器與 llama-server 進 `TownPass/assets/models/` 與 `jniLibs`。要直接產生 APK 與發布檔，改跑 `.\scripts\build-release.ps1`，輸出在 `release\`。

---

## 1. 專案裡有什麼、不在 git 裡的是什麼

| 路徑 | 內容 |
|---|---|
| `TownPass/` | 以 TownPass 開源 App 為基礎的 Flutter App：原生橋接、離線網頁服務、App 內 llama-server |
| `TownPass-Services/` | Vue 3 服務網頁，mock 資料在 `public/mock/` |
| `assistant/` | 小幫手網頁與陪伴引導層；資料在 `public/data/`、導覽腳本在 `public/guides/`、模型在 `public/models/` |
| `tools/` | 資料產生、訓練、爬蟲，見第 3、4 節 |
| `eval/` | 評測腳本與結果 |
| `scripts/` | 建置、打包、手機除錯腳本 |
| `docs/` | 文件、技術圖、截圖 |

**不在 git 裡、要自己準備的東西**

| 東西 | 放哪裡 | 怎麼拿 |
|---|---|---|
| Gemma 決策器權重 `gemma-3-270m-decider-Q8_0.gguf` | `tools/llm/out/` | GitHub Release 下載，或依 [4.3](#43-gemma-決策器) 重訓 |
| llama.cpp Android Snapdragon 版 | `tools/llama-android/snapdragon/llama-b12180/` | [llama.cpp release b12180](https://github.com/ggml-org/llama.cpp/releases/tag/b12180) 的 `llama-b12180-bin-android-arm64-snapdragon.tar.gz`，解壓到此 |
| llama.cpp Windows 版，電腦上執行決策器或量化 GGUF 時才需要 | `tools/llama/` | 同一個 release 的 Windows 版，解壓到此 |
| llama.cpp 轉檔腳本，重訓 Gemma 時才需要 | `tools/llama-src/` | 見 [4.3](#43-gemma-決策器) |
| 訓練中間產物：checkpoint 與 HF 合併權重 | `tools/encoder/ckpt/`、`tools/llm/out/gemma-270m-decider-hf/` | 重訓時自動產生 |
| e5 零樣本模型，只有評測對照組使用 | `assistant/public/models/Xenova/` | `cd assistant; pnpm fetch-embed-model; pnpm precompute` |

e5 分類器放在 `assistant/public/models/cls-services/`，大小 27.5 MB；n-gram 分類器放在 `assistant/public/models/tinycls.*.json`。兩者都在 git 裡，不用另外下載。

---

## 2. 遷移到新電腦

### 2.1 安裝環境

| 工具 | 版本 | 用途 |
|---|---|---|
| Node.js + pnpm | Node 20.17 以上、pnpm 9 | 網頁建置、評測 |
| Python | 3.12 | 資料產生與訓練 |
| Flutter，以 FVM 管理 | 3.47.6，見 `TownPass/.fvmrc` | 編譯 App |
| JDK | 17 | Android 建置 |
| Android SDK + platform-tools | — | 編譯 App、`adb` |
| Git Bash | — | 執行 `scripts/*.sh` |
| 選用：NVIDIA GPU + CUDA 版 PyTorch | — | 重訓模型 |
| 選用：Android NDK 的 clang | — | 只有要重編 `tools/llama-android/stub/` 的兩個小 `.so` 時才需要 |

重訓時需要的 Python 套件：

```powershell
pip install -r tools/requirements.txt
```

PowerShell 腳本透過 `tools/env.ps1` 自動尋找 Flutter 3.47.6、JDK 17 與 Android SDK，涵蓋 FVM、Android Studio 與常見的 JDK 安裝位置。裝在其他位置時，設定 `FLUTTER_HOME`、`JAVA_HOME` 或 `ANDROID_HOME` 即可。

### 2.2 取回程式碼與權重

```powershell
git clone <repo 網址> polaris
cd polaris
# 從 GitHub Release 下載 gemma-3-270m-decider-Q8_0.gguf，放到 tools\llm\out\
# 下載並解壓 llama.cpp b12180 的 Android Snapdragon 版到 tools\llama-android\snapdragon\
fvm install 3.47.6
```

### 2.3 確認環境沒問題

```powershell
cd TownPass-Services; pnpm install; pnpm build-only; cd ..
cd assistant; pnpm install; pnpm build-only; cd ..
node scripts/serve-local.mjs --port 5180      # 開 http://localhost:5180/assistant/，打一句「我要繳水費」
```

輸入我要繳水費後能導向繳水費服務，代表網頁端正常。接著跑 [6.1](#61-離線版-apk) 編一次 APK，確認 App 端也正常。

### 2.4 遷移到另一個 repo，不帶 git 歷史

```powershell
.\scripts\make-clean-export.ps1 -Dest <目的資料夾>
```

它依 `.gitignore` 只複製目前的檔案，不帶 git 歷史、不使用 Git LFS，並掃描敏感字串，最後只執行 `git init`，commit 與 push 由使用者自行操作。私人字串清單放在 `release\sensitive-patterns.txt`，一行一個原樣字串。

---

## 3. 重生資料

資料彼此有依賴，改了上游就要重跑下游。下表依修改內容列出要跑的步驟，步驟編號對應 3.1～3.8。

| 你改了什麼 | 要跑的步驟 |
|---|---|
| 服務頁的版面、按鈕、欄位 | 3.1 → 3.2 → 3.3 → 3.4 → 重訓 Gemma，見 4.3 |
| 服務頁的 mock 資料，例如費用種類、陳情分類、地點 | 3.3 → 3.4 → 重訓全部，見第 4 節 |
| 服務目錄 `assistant/public/data/catalog.json` | 3.3 → 3.4 → 3.5 → 重訓全部 |
| 導覽腳本 `assistant/public/guides/*.json` | 3.4 |
| 訓練用的核心說法 | 3.5 → 重訓全部 |
| 找地點的分類或示範地點 | 3.6 → 3.3 → 3.4 |
| 原 App 入口的靜態示範頁 | 3.7 |
| 測試集 | 3.8 |

跑完之後，依第 6 節重新建置網頁並打包。

### 3.1 建置服務頁並啟動本機伺服器

```powershell
cd TownPass-Services; pnpm build-only; cd ..
cd assistant; pnpm build-only; cd ..
node scripts/serve-local.mjs --port 5180
```

### 3.2 重爬網站地圖 → `assistant/public/data/sitemap.json`

```powershell
node --experimental-websocket scripts/crawl.mjs
```

腳本會啟動無頭 Chrome，在小幫手頁面載入 `tools/crawl/crawler.js`，從現有網站地圖的每一頁出發，再沿著連結探索新頁面。每一頁會列出可互動元素與穩定選擇器，並實際點擊按鈕記錄跳轉目標與展開內容。

- `--fresh`：只從首頁開始探索
- `--out <檔案>`：寫到其他檔案，方便和現有版本比較
- `--port <埠>`：本機伺服器的埠，預設 5180
- 找不到 Chrome 時，用 `CHROME` 環境變數指定瀏覽器路徑

也可以手動執行：在 `http://localhost:5180/assistant/` 的 Console 貼上 `crawler.js`，執行 `await __crawl.all()`，再用 `__crawl.dump()` 取得 JSON。

### 3.3 從服務頁挖訓練句與項目名稱 → `tools/tinycls/data/services.mined.jsonl`、`entities.json`

```powershell
python -I tools/tinycls/mine_mock.py
```

依頁面與服務代號的對應表，從 `TownPass-Services/public/mock/` 與各頁面的中文字串產生句子。新頁面要在腳本裡的對應表加一行。

### 3.4 重建工具表 → `assistant/public/data/registry.json`

```powershell
python -I tools/registry/build_registry.py
python -I tools/llm/gen_ui_data.py        # 由 sitemap 產生「選按鈕」訓練題 → tools/llm/ui_pick.jsonl
```

`build_registry.py` 讀服務目錄、導覽腳本與 `entities.json`，產生每個工具的呼叫方式、參數與項目索引。
需要重新產生自動導覽腳本時，執行 `python -I tools/registry/gen_guides.py`。手寫的繳水費與臨櫃叫號腳本不會被覆蓋。

### 3.5 擴增訓練句 → `tools/tinycls/data/services.generated.jsonl`

```powershell
python -I tools/tinycls/gen_more_data.py
```

核心說法寫在 `gen_more_data.py` 的 `C`，每個服務一組，包含中文名詞、動作、英文與越南語、印尼語、泰語。容易混淆的服務寫在 `CONF`。腳本會乘上開頭、結尾、情境、語音錯字、中英夾雜，並自動去掉和測試集重複的句子。範圍外的句子由 `gen_more_none.py` 產生。

選用：有 GPU 主機時，可以用大模型再擴增一批句子，人工抽查後才納入：

```powershell
python -I tools/tinycls/gen_examples.py --url http://<gpu-host>:8080 --per 40
```

### 3.6 找地點的分類與示範地點

```powershell
python -I tools/gen_find_place.py
```

產生 9 類 46 項的分類樹，以及每項 4 到 8 個示範地點。使用固定 seed，重跑結果相同。公廁與停車場使用真實資料，不會被覆蓋。

### 3.7 原 App 入口的靜態示範頁

```powershell
python -I tools/gen_static_pages.py
```

輸出到 `TownPass-Services/public/<name>/index.html`，下次建置服務頁時會一起打包。

### 3.8 測試集 → `assistant/public/data/testset_1k.json`

測試句是手寫的，放在 `tools/testset/src*.txt`，格式寫在 `src1.txt` 第一行。改完後執行：

```powershell
python -I tools/testset/build_1k.py
```

和訓練句、服務目錄重複的句子會被自動剔除，避免測到背過的題目。

---

## 4. 重訓權重

三個模型共用同一批服務訓練句 `tools/tinycls/data/*.jsonl`。服務目錄或訓練句有變動時，三個都要重訓。

### 4.1 n-gram 分類器

```powershell
python -I tools/tinycls/train.py --set services --eval
python -I tools/tinycls/train.py --set commands
```

輸出 `assistant/public/models/tinycls.services.json`、`tinycls.commands.json`。只用 numpy，不需要 GPU。

### 4.2 e5-small 分類器

```powershell
python -I tools/encoder/train_cls.py --eval
```

微調 `intfloat/multilingual-e5-small` 的分類頭，把詞表從約 25 萬裁到約 1.3 萬，匯出 ONNX int8 到 `assistant/public/models/cls-services/`。

- 已經訓練過、只想重新裁剪與匯出：`--resume`
- 常用參數：`--epochs 12 --lr 5e-5 --batch 16 --max-len 48`

### 4.3 Gemma 決策器

需要 CUDA GPU。第一次要準備 llama.cpp 的轉檔腳本，版本須與手機上的 llama-server 一致：

```powershell
git clone --depth 1 --branch b12180 --filter=blob:none --sparse https://github.com/ggml-org/llama.cpp tools/llama-src
cd tools/llama-src; git sparse-checkout set conversion gguf-py convert_hf_to_gguf.py; cd ../..
```

量化需要 llama.cpp Windows 版的 `tools/llama/llama-quantize.exe`。

**每次重訓：**

```powershell
cd assistant; pnpm -s tsx scripts/dump-prompts.ts; cd ..     # 1. 匯出前端的 prompt → tools/llm/prompts.json
python -I tools/llm/finetune_gemma.py                          # 2. 訓練 → 合併 → 轉 GGUF → 量化
```

- 第 1 步一定要先跑：訓練腳本會核對 prompt 和前端一字不差，不一致就停止。
- 訓練資料：服務訓練句、步驟指令 `commands.jsonl` 與按鈕選擇題 `ui_pick.jsonl` 混合訓練。
- 預設：底座 `unsloth/gemma-3-270m-it`，即 Google Gemma 3 270M 的未 gated 鏡像；LoRA rank 16、3 epochs、lr 2e-4、batch 4 × 累積 4。
- 輸出：`tools/llm/out/gemma-3-270m-decider-Q8_0.gguf`；訓練結束會印出在測試集上的 top-1。
- 只想重新評估已合併的權重：`python -I tools/llm/finetune_gemma.py --eval-only --hf tools/llm/out/gemma-270m-decider-hf`

### 4.4 新權重進 App

```powershell
node scripts/prepare-llama-jni.mjs     # 把 GGUF 與 llama-server 放進 APK 的 assets / jniLibs
```

接著照 [6.1](#61-離線版-apk) 重編 APK。e5 與 n-gram 分類器在網頁資料夾裡，`bundle-web.mjs` 會一起打包。

> 重訓後一定要重跑 `prepare-llama-jni.mjs`，否則 APK 裡還是舊的模型。App 以 APK 的安裝時間判斷要不要重新複製模型，所以只要裝了新 APK，手機上的副本就會更新。

---

## 5. 評測

評測腳本在 `assistant/` 裡執行。

```powershell
cd assistant
pnpm eval --engine cls --fuse                                   # e5 分類器（--fuse = 加上工具表查表融合，和上線行為一致）
pnpm eval --engine tiny --fuse
pnpm eval --engine llm --url http://127.0.0.1:8080 --fuse --name gemma-decider --where laptop-gpu
pnpm matrix                                                     # 彙整 eval/results/*.json → eval/MATRIX.md
```

- 1,027 句測試集：加 `--testset ../assistant/public/data/testset_1k.json --foreign`。一次跑完全部引擎：`bash ../eval/run_1k.sh <名稱>`，再用 `pnpm tsx ../eval/report_1k.ts` 產生 `eval/MATRIX_1K.md`。
- 第二意見，也就是 Gemma 判斷為範圍外時改問 e5：加 `--second cls`。
- 門檻：`--go 0.75 --ask2 0.75 --ask3 0.75`。
- 電腦上跑 Gemma：`tools\llama\llama-server.exe -m tools\llm\out\gemma-3-270m-decider-Q8_0.gguf --port 8080 -ngl 99 -c 4096 --cache-reuse 256`。

**在手機上評測**：使用 App 內的 llama-server，App 開著時執行：

```powershell
adb forward tcp:18080 tcp:8080
cd assistant; pnpm eval --engine llm --url http://127.0.0.1:18080 --fuse --testset ../assistant/public/data/testset_1k.json --foreign --name llm-fuse-phone --where S26-NPU-inapp
```

量到的延遲包含 `adb forward` 約 30 ms。也可以在手機上直接開小幫手的 `#/eval` 頁。

---

## 6. 打包與發布

### 6.1 離線版 APK

```powershell
.\scripts\build-release.ps1
```

依序：建置兩個網頁 → `bundle-web.mjs` 把網頁打包進 `TownPass/assets/web/` → `prepare-llama-jni.mjs` 放入 llama-server 與模型 → `flutter build apk --release` → 在 `release\` 產生 `Polaris-offline.apk`、權重與 `SHA256SUMS.txt`。網頁已經建置過時加 `-SkipWeb`。

`bundle-web.mjs` 會改寫 `TownPass/pubspec.yaml` 的 assets 清單，`build-release.ps1` 結束後會還原；單獨跑 `bundle-web.mjs` 時要自己留意這個檔案的變動。

### 6.2 開發時快速更新手機上的網頁

```powershell
node scripts/bundle-web.mjs
sh scripts/phone-push-web.sh            # 推到手機的覆蓋資料夾，App 重啟後優先讀它
sh scripts/phone-push-web.sh --clear    # 正式展示前一定要清掉，回到 APK 內建版本
```

手機除錯工具：`sh scripts/phone-probe.sh` 顯示陪伴面板與標示框的狀態；`node --experimental-websocket scripts/phone-autowalk.mjs` 自動走完一條導覽並逐步截圖，用法寫在檔案開頭。覆蓋資料夾、WebView 遠端除錯與這些工具只在 debug 版，或用 `.\scripts\build-release.ps1 -DevTools`（`--dart-define=DEV_TOOLS=true`）編的測試版才會開；要發布的 APK 一律不加，三者都關閉。

### 6.3 把模型推到手機的外部資料夾

```powershell
.\scripts\phone-npu.ps1 -PushModel
```

App 會優先使用 `/sdcard/Android/data/com.example.townpass/files/gguf/` 裡的模型。換模型測試時不用重編 APK。

### 6.4 電腦上一鍵啟動開發環境

```powershell
.\scripts\dev-all.ps1          # 建置 → 有模型就啟動 llama-server → 啟動 serve-local（port 5180）
```

手機和電腦在同一個內網時，App 可以用 `--dart-define=DEV_SERVICE_URL=http://<電腦IP>:5180/` 指向電腦。

---

## 7. 新增一個服務

1. **服務頁**：在 `TownPass-Services` 做好頁面與 mock 資料。
2. **服務目錄**：在 `assistant/public/data/catalog.json` 加一筆，包含中英標題、說明、關鍵字、例句與路由。**代號接在最後，不要改動既有服務的代號**，否則 Gemma 學到的對應會亂掉。代號必須是單一字母（A–Z、a–z）。
3. **介面文字**：視需要補上五種語言的 `assistant/public/data/copy.*.json`。
4. **核心說法**：在 `tools/tinycls/gen_more_data.py` 的 `C` 加一組約 30 個說法，在 `CONF` 寫上容易混淆的服務。
5. **擷取句子**：在 `mine_mock.py` 的頁面與代號對應表加上新頁面。
6. **導覽**：手寫 `assistant/public/guides/guide_<id>.json`，或跑 `gen_guides.py`；再依 3.2 重爬網站地圖。
7. **重生資料**：3.3 → 3.4 → 3.5。
8. **重訓**：4.1 → 4.2 → 4.3 → 4.4。
9. **評測**：為新服務另寫 20 到 30 句測試，不要使用產生器的句子，加進 `tools/testset/src*.txt`，跑 3.8 與第 5 節，確認舊服務沒有退步。
10. **打包**：6.1。

---

## 8. 常見問題

| 狀況 | 原因與處理 |
|---|---|
| 重訓後手機上的結果沒變 | 沒有重跑 `prepare-llama-jni.mjs`，APK 裡還是舊模型。重跑後重編、重裝 APK |
| `finetune_gemma.py` 一開始就停止，說 prompt 不一致 | 先在 `assistant/` 跑 `pnpm -s tsx scripts/dump-prompts.ts` |
| PowerShell 腳本出現亂碼或解析錯誤 | 含中文的 `.ps1` 要存成含 BOM 的 UTF-8，Windows PowerShell 5.1 不認得沒有 BOM 的 UTF-8 |
| 手機上的陪伴引導層沒出現 | 覆蓋資料夾裡可能有舊版：`sh scripts/phone-push-web.sh --clear` |
| 離線語音辨識失敗 | 手機要先下載離線語言包：Google App → Settings → Voice → Offline speech recognition |
| 外語翻譯在飛航模式下失敗 | ML Kit 翻譯模型要在有網路時先用過一次，每個語言約 30 MB |
| 麥克風用一用 App 被關掉 | 權限選了僅限這次，改成使用 App 時允許 |
| 地圖底圖是空白 | OpenStreetMap 圖磚需要網路；標記與清單離線也能用 |
