# 第三方授權與資料來源 / Third-Party Notices

本專案的程式碼以 GPL-3.0 釋出（見 [LICENSE](LICENSE)），因為它建立在以 GPL-3.0 授權的臺北城市通 TownPass App 之上。以下列出專案用到的上游專案、模型權重與資料，以及各自的授權。

## 臺北城市通本體

| 項目 | 來源 | 授權 | 用途 |
|---|---|---|---|
| TownPass App（Flutter） | https://github.com/taipei-doit/TownPass | GPL-3.0 | App 殼；本專案加上小幫手入口、離線網頁、原生語音翻譯橋接與手機本地推論 |
| TownPass-Services（Vue 3 微服務範例） | https://github.com/taipei-doit/TownPass-Services | repo 未標示授權 | 被引導的服務頁；本專案補上 13 個示範服務頁與示範資料 |
| TownPass 開發文件 | https://tpe-guideline.web.app/en/docs/ | — | JS bridge 規格 |

## 模型權重

| 模型 | 來源 | 授權 | 本專案的用法 |
|---|---|---|---|
| Gemma 3 270M（Google） | https://huggingface.co/google/gemma-3-270m-it（訓練時使用未 gated 鏡像 https://huggingface.co/unsloth/gemma-3-270m-it） | [Gemma Terms of Use](https://ai.google.dev/gemma/terms) | LoRA 微調成 1-token 決策器，量化為 GGUF Q8_0，在手機 NPU 上執行 |
| multilingual-e5-small（Microsoft） | https://huggingface.co/intfloat/multilingual-e5-small（ONNX 版：https://huggingface.co/Xenova/multilingual-e5-small） | MIT | 微調成服務分類器（備援引擎），裁剪詞表後量化為 ONNX int8 |

**Gemma 聲明**：Gemma is provided under and subject to the Gemma Terms of Use found at ai.google.dev/gemma/terms. 本專案的微調權重 `gemma-3-270m-decider-Q8_0.gguf` 是 Gemma 的衍生模型，散布時同樣受該條款約束，使用時不得違反 [Gemma Prohibited Use Policy](https://ai.google.dev/gemma/prohibited_use_policy)。

## 資料

| 資料 | 提供機關 / 來源 | 授權 | 用途 |
|---|---|---|---|
| 臺北市公廁點位資訊 | 臺北市政府環境保護局，https://data.gov.tw/dataset/138798 | 政府資料開放授權條款第 1 版 | 「找地點」的公廁 |
| 臺北市停車場資訊（TCMSV） | 臺北市停車管理工程處，https://data.gov.tw/dataset/128435 | 政府資料開放授權條款第 1 版 | 「找地點」的停車場 |
| 地圖圖磚 | © OpenStreetMap contributors，https://www.openstreetmap.org/copyright | ODbL | 「找地點」的地圖底圖 |
| 其他 13 個示範服務、找地點 46 個項目的地點、訓練與測試語句 | 本團隊製作的示範資料 | 隨本專案 | 示範與模型訓練 |

## 主要執行期元件

| 元件 | 授權 | 用途 |
|---|---|---|
| llama.cpp b12180（含 Snapdragon / Hexagon 版 Android 建置），https://github.com/ggml-org/llama.cpp | MIT | 在 App 內執行決策器（llama-server） |
| Transformers.js / ONNX Runtime Web | Apache-2.0 / MIT | 在 WebView 內執行 e5 分類器 |
| Google ML Kit（Language ID、Translation，裝置端） | Google APIs Terms of Service | 外語輸入的語言判斷與翻譯 |
| Vue 3、Vite、Leaflet | MIT、MIT、BSD-2-Clause | 前端 |
| flutter_inappwebview、speech_to_text、flutter_tts | Apache-2.0、BSD-3-Clause、MIT | WebView、語音辨識、朗讀 |

其餘相依套件與授權列在各子專案的 `package.json`、`pnpm-lock.yaml` 與 `TownPass/pubspec.yaml`。
