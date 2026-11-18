// ONNX runtime 的 wasm 與載入器由 Vite 打包進小幫手（瀏覽器專用；Node 評測用的是原生 onnxruntime，不會載入這個檔）。
// 不設定的話 transformers.js 會把路徑指到 cdn.jsdelivr.net，有網路時就從外部抓。
import wasm from '../../node_modules/@huggingface/transformers/dist/ort-wasm-simd-threaded.jsep.wasm?url';
import mjs from '../../node_modules/@huggingface/transformers/dist/ort-wasm-simd-threaded.jsep.mjs?url';

export const ORT_PATHS = { wasm, mjs };
