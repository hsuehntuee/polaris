# 技術圖

| 圖 | 內容 |
|---|---|
| `01_architecture` | 系統架構：輸入 → 決策 → 手機本地模型 → 執行與陪伴 |
| `02_decision` | 決策流程：一句話怎麼變成「直接去／追問／找不到」 |
| `03_companion` | 陪伴引導：三層找目標、框住欄位、陪伴節奏 |
| `04_training` | 訓練管線：資料來源、微調、量化、打包與評測 |

每張圖都有 `.svg`（原始檔）和 `.png`（README 用）。規格檔在 `src/`：01 直接維護 `src/01_architecture.json`，02～04 由 `src/build_specs.py` 產生。

用 [fireworks-tech-graph](https://github.com/yizhiyanhua-ai/fireworks-tech-graph)（Style 1 Flat Icon）產生：

```bash
python docs/diagrams/src/build_specs.py
SKILL=~/.claude/skills/fireworks-tech-graph
for f in 01_architecture 02_decision 03_companion 04_training; do
  python "$SKILL/scripts/fireworks.py" render architecture docs/diagrams/src/$f.json docs/diagrams/$f.svg --report docs/diagrams/src/$f.layout.json
  python "$SKILL/scripts/fireworks.py" check docs/diagrams/$f.svg
  sh docs/diagrams/src/svg2png.sh docs/diagrams/$f.svg docs/diagrams/$f.png 1.5   # 沒有 cairosvg / rsvg-convert 時用 Chrome 輸出 PNG
done
```
