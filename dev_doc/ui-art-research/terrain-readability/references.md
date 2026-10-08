# 参考画面观察

已查看原始图像，尺寸和摘要见 `reference-manifest.json`。原图留在仓库外，只研究视觉方法，不复制角色、地形或纹理。

引用入库时必须同时保存实际请求 URL、取得时刻、原字节摘要及来源页引用；核对的是对应原图，不用再次打开商店时随机出现的首图地址补写来源。独立审查须能从该地址重取同一原件，或明确记录来源失效的限制。

## Into the Breach

[开发者在 Steam 发布的截图](https://store.steampowered.com/app/590380/Into_the_Breach/)：雪地图的地面大面积浅亮，山体深色侧面与外轮廓形成连续剪影，雪顶仍保持受光平面。冰冻建筑使用中间明度及清楚的外形，内部细节比边界更碎。

可用于本项目的判断：缩小观看时先检查物体的整体体块与连续边界；若地板噪声与边缘抢对比，单独加几颗高光不足以解决问题。该截图的浅色雪地与 SoT 暗庭院不同，不复制整体明度或像素风。

## Triangle Strategy

[Square Enix 官方战斗预览图](https://www.jp.square-enix.com/trianglestrategy/assets/img/top/battle/movie.png)：左侧抬高的平台以较亮顶面、暗立面区分高低；右上建筑靠顶面、墙面和墙脚的分层建立体积。棋盘格覆盖与角色叠放时，局部依然拥挤，不能据一张营销预览断言该作品所有场景都达到本项目阈值。

可用于本项目的判断：墙顶和侧面应拥有不同的受光层次，不能把铺地纹理直接压暗后同时用作顶面。接地阴影应说明物体站在地面上，宽而黑的周圈容易让墙体读成凹坑。此图只有 699×393，适合观察大关系，不用于规定原生轮廓像素宽度。

## 技术资料用途

[Godot 的多视口与帧后事件](https://docs.godotengine.org/en/4.6/classes/class_renderingserver.html)用于设计同帧采集；[CIEDE2000 作者说明和数据](https://hajim.rochester.edu/ece/sites/gsharma/ciede2000/)用于校准色差计算。T1–T6 的具体阈值来自 Claude 对本项目的审查，不能归因于上述作品或论文。
