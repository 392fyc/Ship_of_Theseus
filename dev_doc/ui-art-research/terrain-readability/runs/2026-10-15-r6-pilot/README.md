# R6 单组云端试点：原件已消费，墙柱修订待审

当前入口是[Claude审查请求](claude-review-request.md)。

- 候选分支codex/ui-ux/terrain-material-r6，提交6ec8a9ffe1ce56005737d1036904d88d1c08a54a。记录分支codex/ui-ux/terrain-r6-evidence，本目录只保存证据与离线诊断。
- TASK117已执行固定单组：calibration_courtyard 10×10、1280×720、Compatibility；五命令各一次，退出码0。
- 595份原件、25,231,569字节、17原PNG、105个运输载体全部精确读回；1487份源码、11次前后快照一致。交付独审PASS。
- 正式结果FAIL保留。墙T1为1PASS/5FAIL/1NOT_TESTED；柱T1/T6各3FAIL。T2墙7/7与柱3/3通过；树T3为12/12、C9为11/12，树图冻结。
- 新发现R6-MASK-INTERNAL-SEAM-01：末次半透明线条的source alpha被当作整个实例占据，内部接缝形成假孔洞并进入组外轮廓。原像素与实际不透明底层多边形见internal-seam-proof.json；正式结果没有改写。
- 两名无上下文观察者仍有石桩、墓碑或石块等替代判断，柱辨识门槛FAIL。T4接地为待Claude复核的离线诊断；T5地面控制921600像素RGBA与TASK115一致。
- RECEIPT118正文与交付均经独立审查，已签名、上传并API精确读回；Main原生采用先于一次seq136通知。关闭ACK已精确读回并核对原YC采用；实际账本closed/count1。完整绑定在closure-verification.json。

## 证据分工

- result.original.json、full-original-map.original.json：Dot原文与精确完整映射。
- original-readback-verification.json：全部595份原件及105载体的逐文件尺寸/SHA256。
- main-runtime-verification.json：11份来源状态、五命令、图像一致性、C4/C8和冻结复算。
- captures/main.png：本轮原图，未缩放或改色。其余16图按完整映射读取。
- material-analysis.json、analysis/：离线诊断，来源与处理步骤在analysis/processing.md；不替代原图或正式结果。
- task117-delivery-independent-review.json、receipt118-independent-review.json：独立审查原文；签名绑定另见receipt118-signature-binding.json。
- main-consumption.json为签收前冻结快照，其protocol_close字段保留当时状态；后续关闭事实另存closure-verification.json。

树图、地面、接壤、水深、网格、镜头、占格、玩法和阈值均冻结。下一步审查测量修复及柱体辨识，不扩大到六组。
