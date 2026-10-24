# 首页堆叠海报轮播

2026-10-22：根据用户提供的音乐应用截图，将猫源与Emby的共享3D转盘改为Cover Flow排布。中央海报正面靠前，两侧后退、倾斜并被中央部分遮挡。沿用竖版海报完整显示，不添加截图中的白框、投影、模糊底图或独立矩形遮罩。

## 布局与动效

- 海报宽度使用舞台宽度的54%，仍限制在144～260 vp；舞台最大720 vp，保留原有图片比例自适应与图像自身的圆角裁切。
- 静止侧卡缩放0.84，Y轴旋转约±40°，后退40 vp并下移12 vp；正常相邻卡保持不透明，避免重叠时透出另一张海报。调暗采用图片内部28%黑色蒙层，与图片一起裁切圆角，不再对透明占位容器使用brightness滤镜。
- 侧卡中心相对中央的水平距离为海报宽度的0.62倍，补偿Swiper原有20 vp间隔。相比初版0.72倍增加静止遮挡，按保守投影模型在常规竖海报样本中形成约18%～26%宽度的重叠，同时保留可见的侧面。不同原图比例会改变实际遮挡量。
- 两张主卡交接时增加一段连续的水平间隙，使前后绘制层级在卡片分离时交换。间隙直接由原生滚动进度计算，端点速度、加速度连续；不另起回弹或停稳后的二次展开动画。
- 同一个Swiper的直接子节点用zIndex设置绘制顺序。海报内部原生Stack统一使用transform3D，不在自定义组件外层叠加scale／rotate／translate，不逐帧修改宽高、间距等布局属性。
- HomeCarouselProjection按列优先生成Txy × P × Tz × Ry × S矩阵，显式包含齐次透视项；其非零投影项会使侧卡上下边产生斜率，而不是只缩小成平面矩形。摄像机距离为海报宽度的2.8倍，所有平移／相机参数通过当前UIContext.vp2px(1)换算成物理像素。
- 保留单一滚动进度用于所有卡片、文字、指示器和背景取色。点击侧海报及指示点与自动切换统一为720 ms，并使用同一自动缓动曲线，避免总时长一致但前段仍显得过快。拖动收尾保持420 ms及原手动曲线，交互暂停策略继续沿用。
- 点击启动分为参数更新和原生翻页两个阶段：先写入720 ms及自动曲线，再通过FrameCallback.onIdle在该帧UI更新后调用SwiperController。不能在同一个点击回调中写入状态后立即翻页，否则原生组件可能继续读取触摸按下时已应用的420 ms及拖动曲线。等待期间阻止重复点击并暂停自动播放，新触摸、页面隐藏、后台、源或外部选项变化会使旧任务失效。

Swiper开启cachedCount(1, true)绘制相邻缓存页，使被平移拉入舞台的侧卡不必等到原始页面边界进入视窗才绘制。现有最少6个循环显示槽继续保留，避免少量作品的循环左右两端复用同一原生页。外侧卡逐渐淡出，距离中心超过1.01页的节点不参与点击命中；轮播切换期间的业务点击保护继续生效。最终交互命中区域仍需设备确认。

收到“两页滑动有方框阴影、静止像平铺”的反馈后，移除整块透明槽位上的brightness、renderGroup及逐帧opacity。离屏分组仅包含实际图片边界内的图片和调暗蒙层，内层先裁切圆角，再由外层原生Stack整体做3D投影；外侧槽位淡出仅作用于这块紧贴图片的节点。图片加载淡入与按压缩放留在内部，不给每帧投影及淡出增加独立隐式动画。以上是针对合成伪影的实现修正，实际系统绘制仍需设备确认，不能从源码和几何测试断言伪影已在设备上消失。

点击侧卡先居中，点击停稳的中央卡进入原作品详情。首页分类tab、其沉浸光感、订阅管理、聚合搜索和上一轮首屏缓存修复均保持原样。

## 接口依据

- [Swiper](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-swiper)：原生滑动、循环、缓存页绘制及子节点层级。
- [图形变换](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-transformation)：API20的transform3D，低于项目API23下限。
- [matrix4](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-matrix4)：列优先矩阵、物理像素单位及齐次透视项。
- [Z序控制](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-z-order)：同一容器兄弟节点的覆盖关系。
- [图像效果](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-image-effect)：renderGroup使用离屏画布，其不透明度不为1时可能出现不同绘制结果；本版不再对完整透明槽位做分组／滤镜。
- [UIContext](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uicontext-uicontext)：vp2px使用当前UI实例的像素密度。

## 验证边界

回归使用实际布局／动效／投影函数，覆盖尺寸、完整图片比例、运动单调性及端点连续性、叠放范围、交接间隙、纵向边界、循环首尾、双向多圈切换、真实作品标识、交互暂停和逐帧颜色进度。增加实际矩阵在竖图、方图、横图上的侧边斜率、左右镜像及不同像素密度投影一致性，中央保持无畸变。几何检查不模拟原生光栅化、命中分发或设备合成器。

按用户此前要求不自动安装或调试设备；实际遮挡、手感、圆角抗锯齿与帧率尚未进行设备确认。本版构建与测试结果记录在tmp/cover-flow-depth-evidence.json；初版记录保留在tmp/cover-flow-evidence.json。

2026-10-22点击时序复核：log.txt中Swiper 679有6次未中断的快速点击切换用时424～444 ms，另有一次741 ms；一次416 ms的切换被下一次按下强制结束，单独排除。日志证明点击切换仍有接近420 ms的实际时长，结合代码判断为状态批量更新与即时控制器调用之间的时序问题；首个741 ms事件不能仅凭该日志片段判定为自动轮播。新增回归模拟已提交的原生参数与尚未提交的声明式状态，修复前捕获420 ms／拖动曲线，修复后捕获720 ms／自动曲线。设备上的修复后实际时长尚未采集；构建、包校验和日志分析记录见tmp/carousel-click-commit-evidence.json及tmp/carousel-click-log-review.json。
