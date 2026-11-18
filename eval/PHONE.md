# On-phone numbers (Galaxy S26 Ultra, 2026-11-08)

Same test set as `MATRIX_1K.md` (1,027 utterances), decider served by the llama-server running **inside the TownPass APK** on the Hexagon NPU (`llm-fuse-phone` row), measured over `adb forward` from the laptop (adds ~30 ms per request).

| run | where | first-round | two-round | out-of-scope | p50 | p90 | max |
|---|---|---|---|---|---|---|---|
| llm-fuse-phone | S26 NPU, in-app | 93.2% | 97.3% | 99.2% | 63 ms | | |
| llm-fuse-review | laptop RTX GPU | 93.4% | 97.4% | 99.2% | 42 ms | | |
| cls-fuse-r3 | e5 classifier, WebView ONNX | 94.9% | 96.8% | 90.6% | 6 ms | | |

| llm-fuse-phone-2nd | S26 NPU + e5 second opinion | 93.2% | 97.4% | 99.2% | 64 ms | | |

Phone and laptop agree on every item class; repeated phone runs land between 93.6% and 93.9% first-round (3 items at the ASK threshold).

## Second opinion (shipped)

The decider says "out of scope" for some phrasings that a Taipei resident would expect to work, e.g. 我想看漫畫 (library has comics). Instead of a keyword rule, the app asks a second model: when Gemma answers NONE with p < 0.995 **and** the sentence contains an unambiguous catalog term, the e5 classifier (already loaded as the fallback, 6 ms) scores the sentence; only if its top choice is one of the services the term points to, with p >= 0.8, does the app go there (still shown as a confirm, "要去【X】嗎？"). The lexicon never decides, it only decides when to ask the second model. Effect on the 1k set: out-of-scope detection unchanged (99.2%), first-round unchanged, one already-missed item becomes a confirm instead of "not found"; all 12 comic/book phrasings that used to dead-end now route to the library. The eval CLI reproduces it with `--second cls`.

Code review (2026-11-19): the 0.8 threshold used to be checked after the registry fusion, which lifts the candidate and made it effectively 0.2–0.3. It is now checked on the classifier's own probability, as described above. On the 1,027 set no item changes (`llm-fuse-2nd-review` equals `llm-fuse-review`); the `llm-fuse-phone-2nd` row was measured under the old rule. 我想看漫畫 (e5 0.988) and 想看屁屁偵探 (e5 0.810) still go to the library.

## NPU vs CPU on the same phone, same model, same server build

`scratchpad/coldbench.py`: 1-token decision, prompt ≈ 610 tokens, 6 runs each, p50.

| | cold prompt (prefix not cached: new page / new option list) | cached prefix (service decision, 1 new token) |
|---|---|---|
| Hexagon NPU (in-app) | **94 ms** | 16 ms |
| CPU, 6 threads (`--device none`) | 318 ms | 11 ms |

- Service-picking prompts share one fixed prefix, so after the first call both paths are a few ms and the latency is dominated by HTTP + WebView. The NPU wins on the prompts that change per page (companion "which button" picks, step-context commands): 3.4x faster and the CPU cores stay free for speech recognition, TTS and the WebView.
- Memory: the Q8 GGUF is 292 MB on disk; the in-app server holds it plus a 2048-token context.
