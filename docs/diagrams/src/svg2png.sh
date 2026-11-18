#!/bin/sh
# SVG → PNG（本機沒有 cairosvg / rsvg-convert 時，用 headless Chrome 截圖）
# 用法：sh docs/diagrams/src/svg2png.sh <in.svg> <out.png> [scale]
in="$1"; out="$2"; scale="${3:-1.5}"
wh=$(python -I -c "import re,sys;s=open(sys.argv[1],encoding='utf-8').read(2000);m=re.search(r'viewBox=\"0 0 ([0-9.]+) ([0-9.]+)\"',s);print(int(float(m.group(1))),int(float(m.group(2))))" "$in")
w=${wh% *}; h=${wh#* }
abs=$(cd "$(dirname "$in")" && pwd -W)/$(basename "$in")
outabs=$(cd "$(dirname "$out")" && pwd -W)/$(basename "$out")
"/c/Program Files/Google/Chrome/Application/chrome.exe" --headless=new --disable-gpu --hide-scrollbars \
  --force-device-scale-factor="$scale" --window-size="$w,$h" --default-background-color=FFFFFFFF \
  --screenshot="$outabs" "file:///$abs" >/dev/null 2>&1
python -I -c "from PIL import Image;import sys;print(sys.argv[1],Image.open(sys.argv[1]).size)" "$out"
