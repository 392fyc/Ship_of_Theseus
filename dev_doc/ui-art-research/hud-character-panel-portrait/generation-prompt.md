# 剑圣头像生成记录

- 方式：Codex 内置 imagegen，编辑参考图。
- 参考原画：`res://assets/prototype/visual_style/samples/portrait_preview_final.png`，SHA256 `9f123a2022abe62472530ebd13ba43587802623c0db7ff7af711f5cec5be0cf3`。
- 输出素材：`res://assets/ui/portraits/kensei_hud_portrait_generated.png`，SHA256 `1b8fc2322dae3f141a0a342a2d11e2604351bad8d36912f8538b908905267105`。
- 裁切：`Rect2(320, 100, 660, 735)`；画框中的显示区域为 70×78 像素。
- 用户裁决：2026-09-24 对照 Godot 正式画面后，选择重新生成版。

## 原始提示词

> Use case: identity-preserve. Asset type: a single original game HUD character portrait, intended to display at 70 x 78 px inside an existing frame. Input image 1 is the approved character artwork; use the LEFT-hand red-haired sword saint only as the identity and costume reference. Create a tightly framed head-and-shoulders portrait in a 7:8 vertical composition with the face, bangs, crimson hair, red eyes, high black armored collar, and fine muted gold costume details recognizably consistent with that left figure. Her expression is composed and severe. Correct the facial rendering: replace the large pure-white geometric patches on forehead, nose, and cheek with softly blended, warm pale skin tones and restrained natural highlights; no blocky white areas. Preserve the dark crimson/black/gold painterly fantasy style and clear facial features at small UI size. Fill every edge of the rectangular canvas with either hair, shoulders, or a very dark burgundy/charcoal background so no transparent corner or inset margin appears. Output only the portrait artwork, without an interface frame, sword, extra figures, lettering, watermark, checkerboard, or UI elements.
