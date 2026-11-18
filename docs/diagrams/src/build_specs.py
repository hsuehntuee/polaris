"""產生 docs/diagrams/src/02～04 的 JSON 規格（fireworks-tech-graph 的 architecture 模式）。
01 架構圖的規格直接維護在 01_architecture.json。

  python docs/diagrams/src/build_specs.py
  然後依 docs/diagrams/README.md 的指令 render → check → 匯出 PNG。
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
X = [60, 330, 600, 870, 1140]
W, H = 200, 70
WIDE = {'sent': 470}
C = {'plain': ('#ffffff', '#cbd5e1'), 'blue': ('#eff6ff', '#3b82f6'), 'violet': ('#faf5ff', '#8b5cf6'),
     'teal': ('#f0fdfa', '#14b8a6'), 'orange': ('#fff7ed', '#f97316'), 'green': ('#f0fdf4', '#22c55e'), 'red': ('#fef2f2', '#ef4444')}


def spec(name, title, subtitle, bands, nodes, arrows, legend, footer):
    by, containers, y = {}, [], 110
    for bid, label in bands:
        by[bid] = y
        containers.append(dict(id=bid, x=40, y=y, width=1320, height=140, label=label))
        y += 190
    out = []
    for i, col, band, label, sub, *rest in nodes:
        color = rest[0] if rest else 'plain'
        kind = rest[1] if len(rest) > 1 else 'rect'
        fill, stroke = C[color]
        out.append(dict(id=i, kind=kind, x=X[col], y=by[band] + 46, width=W, height=H,
                        label=label, sublabel=sub, fill=fill, stroke=stroke, flat=True))
    for n in out:
        if n['id'] in WIDE:
            n['width'] = WIDE[n['id']]
    arr = [dict(id=f'e{k}', source=s, target=t, source_port=sp, target_port=tp, flow=fl, label=lb)
           for k, (s, sp, t, tp, fl, lb) in enumerate(arrows)]
    h = y + 70
    d = dict(schema_version=1, mode='architecture', template_type='architecture', style=1, quality_profile='showcase',
             text_policy='strict', width=1400, height=h, title=title, subtitle=subtitle, containers=containers,
             nodes=out, arrows=arr, legend_orientation='horizontal', legend_x=48, legend_y=h - 90, legend_locked=True,
             legend=[dict(flow=f, label=l) for f, l in legend])
    if footer:
        d.update(footer=footer, footer_x=48, footer_y=h - 40)
    with open(os.path.join(HERE, name + '.json'), 'w', encoding='utf-8') as fh:
        json.dump(d, fh, ensure_ascii=False, indent=1)


spec('02_decision', '決策流程', '一次推論取得每個工具代號的機率，再依固定規則決定下一步',
     [('A', '① 算出機率分布'), ('B', '② 決策規則，門檻 0.75'), ('C', '③ 三種結果，下一步由使用者決定')],
     [('say', 0, 'A', '一句話', '語音或打字', 'blue', 'user_avatar'),
      ('lang', 1, 'A', '語言判斷', '外語先翻成中文'),
      ('llm', 2, 'A', '決策器', 'Gemma 只算 1 個 token', 'violet', 'double_rect'),
      ('second', 3, 'A', '第二意見', '說找不到時 e5 再看', 'violet'),
      ('fuse', 4, 'A', '查表融合', '講到項目名就拉高'),
      ('rule', 2, 'B', '決策規則', '比較前三名的機率', 'orange'),
      ('ask', 1, 'C', '追問', '2～3 顆按鈕・最多兩輪', 'blue'),
      ('go', 2, 'C', '直接去', '先顯示確認卡', 'teal'),
      ('none', 3, 'C', '找不到', '看全部服務・撥 1999', 'red')],
     [('say', 'right', 'lang', 'left', 'control', '文字'),
      ('lang', 'right', 'llm', 'left', 'control', '中文'),
      ('llm', 'right', 'second', 'left', 'data', '機率'),
      ('second', 'right', 'fuse', 'left', 'data', '機率'),
      ('fuse', 'bottom', 'rule', 'right', 'control', '分布'),
      ('rule', 'left', 'ask', 'top', 'control', '前 2～3 名 ≥ 0.75'),
      ('rule', 'bottom', 'go', 'top', 'control', '第一名 ≥ 0.75'),
      ('rule', 'right', 'none', 'top', 'feedback', '其他')],
     [('control', '判斷流程'), ('data', '機率'), ('feedback', '出口')],
     '')

spec('03_companion', '陪伴引導', '引導層疊加在原服務頁上，由使用者自行操作',
     [('A', '① 三層定位，依序嘗試'), ('B', '② 標示目標欄位'), ('C', '③ 引導強度')],
     [('start', 0, 'A', '這一步的目標', '例：輸入水號', 'blue'),
      ('script', 1, 'A', '導覽腳本', '31 份・文字與標籤定位'),
      ('sitemap', 2, 'A', '網站地圖', '31 頁・BFS 找路'),
      ('layout', 3, 'A', '版面打分', '即時掃描，模型挑一個', 'violet'),
      ('textonly', 4, 'A', '只給文字說明', '不標示任何位置', 'red'),
      ('spot', 2, 'B', '點亮目標', '其他地方變暗・一句話', 'teal', 'double_rect'),
      ('act', 2, 'C', '使用者自己操作', '點、打字、用說的填', 'blue'),
      ('pay', 1, 'C', '付款與送出', '只點亮，本人按', 'orange'),
      ('retreat', 3, 'C', '退到角落', '連兩步自己完成', 'plain'),
      ('back', 4, 'C', '再出現', '卡住 45 秒或點它', 'teal')],
     [('start', 'right', 'script', 'left', 'control', '找'),
      ('script', 'right', 'sitemap', 'left', 'feedback', '找不到'),
      ('sitemap', 'right', 'layout', 'left', 'feedback', '找不到'),
      ('layout', 'right', 'textonly', 'left', 'feedback', '找不到'),
      ('script', 'bottom', 'spot', 'left', 'control', '找到'),
      ('sitemap', 'bottom', 'spot', 'top', 'control', '找到'),
      ('layout', 'bottom', 'spot', 'right', 'control', '找到'),
      ('spot', 'bottom', 'act', 'top', 'control', '換你'),
      ('act', 'left', 'pay', 'right', 'control', '最後一步'),
      ('act', 'right', 'retreat', 'left', 'control', '會了'),
      ('retreat', 'right', 'back', 'left', 'feedback', '卡住')],
     [('control', '主要流程'), ('feedback', '退一步或條件觸發')],
     '')

spec('04_training', '訓練管線', '兩個模型共用同一批服務訓練句，輸出都是單一選項',
     [('A', '① 訓練資料'), ('B', '② 微調'), ('C', '③ 量化'), ('D', '④ 打包與評測')],
     [('hand', 0, 'A', '手寫核心說法', '每個服務約 30 個', 'blue'),
      ('tmpl', 1, 'A', '模板擴增', '口語・錯字・中英夾雜'),
      ('sent', 2, 'A', '服務訓練句', '約 6,300 句', 'green'),
      ('mine', 4, 'A', '從服務頁挖句子', 'mock 資料・頁面文字', 'teal'),
      ('crawl', 0, 'B', '爬網站地圖', '31 頁可點元素', 'teal'),
      ('ui', 1, 'B', '選按鈕題目', '965 題・選項每題打亂', 'green'),
      ('gemma', 2, 'B', 'Gemma 3 270M', 'LoRA r16・只學 1 個字母', 'violet', 'double_rect'),
      ('cls', 3, 'B', 'e5-small 分類器', '微調分類頭・裁詞表', 'violet'),
      ('gguf', 2, 'C', 'GGUF Q8_0', '292 MB・llama.cpp'),
      ('onnx', 3, 'C', 'ONNX int8', '27.5 MB・WebView'),
      ('apk', 3, 'D', '離線 APK', '模型與網頁都在裡面', 'teal', 'double_rect'),
      ('eval', 4, 'D', '1,027 句測試', '首輪 93～95%', 'orange')],
     [('hand', 'right', 'tmpl', 'left', 'data', '乘上變化'),
      ('tmpl', 'right', 'sent', 'left', 'data', '加入'),
      ('mine', 'left', 'sent', 'right', 'data', '加入'),
      ('crawl', 'right', 'ui', 'left', 'data', '出題'),
      ('ui', 'right', 'gemma', 'left', 'data', '混著練'),
      ('sent', 'bottom', 'gemma', 'top', 'data', '服務題'),
      ('sent', 'bottom', 'cls', 'top', 'data', '同一批句子'),
      ('gemma', 'bottom', 'gguf', 'top', 'control', '合併量化'),
      ('cls', 'bottom', 'onnx', 'top', 'control', 'int8'),
      ('gguf', 'bottom', 'apk', 'left', 'control', '打包'),
      ('onnx', 'bottom', 'apk', 'top', 'control', '打包'),
      ('apk', 'right', 'eval', 'left', 'feedback', '手機實測')],
     [('data', '資料'), ('control', '建置'), ('feedback', '評測')],
     '')
print('ok')
