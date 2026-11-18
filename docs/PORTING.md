# 移植指引：其他 Android 手機、iPhone 與網頁版

這份文件說明 Polaris 台北通小幫手在不同平台上的執行方式、哪些部分與平台相依，以及移植到新平台的步驟與驗證方法。實機驗證過的機型是 Galaxy S26 Ultra；其他平台的內容依程式結構與打包內容整理，移植時請依第 6 節逐項驗證。

---

## 1. 各部分的平台相依性

| 部分 | 位置 | 平台相依性 |
|---|---|---|
| 小幫手網頁、陪伴引導層 | `assistant/` | 無，任何現代瀏覽器或 WebView 都能執行 |
| e5 分類器、n-gram 分類器 | `assistant/public/models/` | 無，在網頁內以 WASM 執行 |
| 服務頁 | `TownPass-Services/` | 無 |
| 語音辨識、語言判斷、翻譯、朗讀 | `TownPass/lib/util/web_message_handler/tp_assistant_message_handler.dart` | 使用 speech_to_text、Google ML Kit、flutter_tts，三者都支援 Android 與 iOS |
| 引導層注入 | `TownPass/lib/service/assistant_service.dart` | 使用 flutter_inappwebview 的 initialUserScripts，Android 與 iOS 都支援 |
| App 內推論伺服器 | `TownPass/lib/service/llm_server_service.dart`、`MainActivity.kt`、`TownPass/android/app/src/main/jniLibs/`、`tools/llama-android/stub/` | Android 專用，以 JNI 在 App 程序內啟動 llama-server |
| 離線網頁 | `TownPass/lib/service/offline_web_service.dart` | Android 專用，攔截 WebView 對 `http://townpass.local/*` 的請求，改由 APK 內的檔案回應 |

網頁端的決策器介面會依序嘗試可用的引擎：App 內的 llama-server、設定的 LLM 網址、e5 分類器、n-gram 分類器。因此任何平台只要能開啟小幫手網頁，至少都能使用 e5 分類器完成語意導航。

---

## 2. Android

### 2.1 NPU 支援範圍

APK 內含 llama.cpp b12180 Snapdragon 版的 Hexagon NPU 函式庫，共五個版本：`libggml-htp-v73.so`、`v75`、`v79`、`v81`、`v85`。llama.cpp 會依手機的 Hexagon 版本載入對應的函式庫。依 Qualcomm 的版本對應，Snapdragon 8 Gen 2 以後的旗艦晶片都在這個範圍內。Galaxy S26 Ultra 使用 v81，已完成實機驗證。

App 透過 `AndroidManifest.xml` 的 `uses-native-library` 宣告 `libcdsprpc.so` 與 `libadsprpc.so`，讓 App 程序可以存取廠商提供的 NPU 通訊函式庫；這兩項都設為非必要，所以沒有這些函式庫的手機仍可正常安裝。

### 2.2 其他晶片

聯發科天璣、三星 Exynos、Google Tensor 與較舊的 Snapdragon 沒有對應的 Hexagon NPU。App 內的 llama-server 無法使用時，小幫手會自動改用其他引擎：

- 語意導航由 WebView 內的 e5 分類器負責，延遲約 6 毫秒，在 1,027 句測試集上第一輪命中 94.9%。
- 陪伴引導的第三層定位使用規則打分。
- llama-server 的啟動結果與實際使用的引擎，可在開發者儀表板確認，見 2.4。

若要在這類手機上也使用 Gemma 決策器，可以讓 llama-server 以 CPU 執行。實測數據：同一支手機以 6 個 CPU 執行緒執行，前綴未快取時 318 毫秒，快取後 11 毫秒。調整位置在 `llm_server_service.dart` 的伺服器啟動流程：NPU 無法使用時，改以 CPU 參數啟動 llama-server，也就是 `--device none` 搭配 `-t` 指定執行緒數。

### 2.3 移植到新的 Android 機型

1. 依 `docs/MAINTENANCE.md` 第 6.1 節產生 APK，安裝到目標手機。
2. 開啟小幫手，確認語音、翻譯、導覽可正常使用。
3. 依 2.4 確認 llama-server 的狀態與實際使用的引擎。
4. 依第 6 節跑一次評測，比較命中率與延遲。

### 2.4 確認執行狀態

- **開發者儀表板**：在小幫手主畫面連點標題三下，或長按 1.2 秒。畫面會分別顯示實際使用的引擎，以及 llama-server 的健康檢查結果。
- **系統記錄**：`adb logcat -s llm-server`，可看到 NPU 函式庫載入與伺服器啟動的過程。
- **直接檢查伺服器**：`adb forward tcp:18080 tcp:8080` 之後，在電腦上開啟 `http://127.0.0.1:18080/health`。

---

## 3. iPhone

### 3.1 可以直接沿用的部分

- 小幫手網頁、陪伴引導層、e5 與 n-gram 分類器：在 iOS 的 WebView 中可直接執行。
- 語音辨識、語言判斷、翻譯、朗讀：使用的 Flutter 套件都支援 iOS。
- 引導層注入：flutter_inappwebview 在 iOS 上同樣支援。

### 3.2 需要移植的部分

| 項目 | Android 現行做法 | iOS 建議做法 |
|---|---|---|
| 網頁來源 | 攔截 `http://townpass.local/*`，由 APK 內檔案回應 | 兩種選擇：一是由伺服器提供網頁，以 `DEV_SERVICE_URL` 與 `ASSISTANT_URL` 指向該網址；二是改用自訂網址 scheme，以 flutter_inappwebview 的自訂 scheme 功能，或 iOS 的 `WKURLSchemeHandler`，由 App 內的檔案回應。第二種可離線使用，且 Android 也能共用同一套做法 |
| Gemma 決策器 | llama-server 以 JNI 在 App 程序內啟動，使用 Hexagon NPU | 將 llama.cpp 編譯為 iOS 函式庫，使用 Metal 在 iPhone GPU 上執行。iOS 不能另外啟動子程序，做法與 Android 相同：在 App 程序內以背景執行緒啟動 llama-server，監聽 `127.0.0.1:8080`，網頁端就不需要任何修改。llama.cpp 原始碼附有 `build-xcframework.sh` 可產生 iOS 函式庫 |
| 模型檔 | 打包在 APK，第一次啟動時複製到私有目錄 | 打包在 App bundle，或首次啟動時下載到 App 的資料夾。GGUF Q8_0 大小 292 MB，需留意 App 大小與下載策略 |
| 權限 | Android 麥克風權限 | 在 `TownPass/ios/Runner/Info.plist` 加上麥克風與語音辨識的用途說明 `NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription` |

若要使用 Apple Neural Engine，llama.cpp 並不支援，需要另外把模型轉成 Core ML 格式，並以 Core ML 推論取代 llama-server。這條路線的工作量較大，建議先以 Metal 版本完成移植。

### 3.3 建議的移植順序

1. **連線版**：在 Mac 上以 Flutter 3.47.6 編譯 iOS 版，網頁由伺服器提供，使用 e5 分類器。這一步不需要寫原生程式，可以先確認語音、翻譯、導覽在 iOS 上的表現。
2. **離線網頁**：改用自訂網址 scheme，從 App 內提供網頁。
3. **Gemma 決策器**：整合 llama.cpp 的 Metal 版本，在 App 程序內啟動伺服器。
4. **驗證**：依第 6 節跑評測與實機流程。

### 3.4 環境需求

- Mac 與 Xcode，用於編譯與簽署。
- Flutter 3.47.6，版本見 `TownPass/.fvmrc`。
- iOS 部署目標：`TownPass/ios` 目前設定為 15.0 以上；ML Kit 套件的最低版本要求以該套件的說明為準。
- 實機測試需要 Apple 開發者帳號。

---

## 4. 網頁版

小幫手與服務頁可以部署為一般網站，任何瀏覽器都能使用，適合桌機或尚未安裝 App 的情境。

- 部署方式：`deploy/` 的 Docker 設定，或任何靜態網站伺服器，服務頁放在根目錄、小幫手放在 `/assistant/`，並在服務頁的 `</head>` 前注入 `/assistant/guide-overlay.js`。`deploy/nginx.conf` 是完整範例。
- 決策器：伺服器上執行 llama-server 並把 `/llm/` 轉發過去；沒有 llama-server 時，網頁使用 e5 分類器。
- 語音與翻譯：網頁版沒有原生橋接，改用瀏覽器的 Web Speech API；外語翻譯在網頁版不提供。

---

## 5. 各平台功能對照

| 功能 | Android Snapdragon | 其他 Android | iPhone 連線版 | iPhone 完整移植後 | 網頁版 |
|---|---|---|---|---|---|
| 語意導航 | Gemma，NPU | e5 分類器 | e5 分類器 | Gemma，Metal | e5 分類器或伺服器上的 Gemma |
| 陪伴引導 | 完整 | 完整，第三層定位使用規則打分 | 完整，第三層定位使用規則打分 | 完整 | 完整，第三層定位使用規則打分 |
| 離線語音 | 支援 | 支援 | 支援 | 支援 | 依瀏覽器 |
| 外語翻譯 | 裝置端 | 裝置端 | 裝置端 | 裝置端 | 不提供 |
| 飛航模式 | 支援 | 支援 | 不支援 | 支援 | 不支援 |
| 實機驗證 | Galaxy S26 Ultra | 待驗證 | 待驗證 | 待驗證 | 電腦瀏覽器已驗證 |

---

## 6. 移植後的驗證

1. **評測**：使用 1,027 句測試集，比較第一輪命中、兩輪內命中、範圍外辨識與延遲。
   - App 內的小幫手：開啟 `#/eval` 頁面直接執行。
   - Android：`adb forward tcp:18080 tcp:8080` 後，在電腦上執行 `pnpm -C assistant eval --engine llm --url http://127.0.0.1:18080 --fuse --testset ../assistant/public/data/testset_1k.json --foreign`。
   - 參考數據見 `eval/MATRIX_1K.md` 與 `eval/PHONE.md`。
2. **流程**：至少走完繳水費、找公廁、陳情三條導覽，並在長輩模式下走一次付款流程。Android 可用 `scripts/phone-autowalk.mjs` 自動操作並逐步截圖，用法寫在檔案開頭。
3. **離線**：開啟飛航模式，確認導航、引導與語音辨識仍可使用。
4. **儀表板**：確認實際使用的引擎與預期一致，延遲在合理範圍內。
