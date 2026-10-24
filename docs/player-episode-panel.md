# 播放页选集面板

2026-10-23。

## 入口与布局

播放页底部工具组顺序为：倍速、list_bullet 选集、屏幕旋转。横屏播放主控继续居中，工具组靠右；竖屏将主控和工具组分行，避免三个功能按钮与前后集、快进快退重叠。

面板由原生 CustomDialogController 承载，横屏右侧对齐、宽 44%/高 88%，竖屏底部对齐、宽 94%/高 62%，均遵循系统弹窗安全区和最大尺寸限制。边缘留出 12vp，圆角 24vp，轻遮罩保留视频内容。旋转改变横竖布局时先关闭旧面板，再次打开使用当前布局。

内容包括作品名、当前浏览线路的集数、横向线路选择、双列集数、正倒序、关闭按钮。当前播放项以蓝色和播放符号标识，判断包含来源、媒体 ID、线路 ID；倒序仅改变面板索引，不改变实际队列或前后集顺序。长集名最多显示两行，完整名称提供给无障碍读取。滚动条隐藏。

## 组件级沉浸光感

使用 CustomDialogControllerOptions.systemMaterial 配置原生 ImmersiveMaterial，customStyle 保持 false。设置页的 materialThickness 在每次打开时读取，映射全部五种厚度，开启 colorInvert 与 applyShadow。内容根背景透明，不额外叠加不透明背板或通用模糊遮挡原生材质。

普通布局容器通过通用 systemMaterial 设置材质存在标题栏/底部 TabBar 生效区域约束，因此没有用普通 Column 浮层冒充已生效的材质。原生弹窗的 systemMaterial 是官方列出的组件级入口。customStyle=true 会使弹窗沉浸光感失效，不能为绕过系统尺寸约束而开启。

API 23–25、设备不支持、应用关闭材质或能力查询失败时，保留主题卡片背景和可读内容。文本使用系统前景资源，选中强调色沿用项目蓝色。原生材质日志记录配置成功，不宣称日志可证明实际渲染效果。

## 线路与播放行为

PlaybackQueueGroup 是统一播放模型，包含线路 ID、名称及完整集数队列。猫源 Provider 在已读取的作品详情中生成各线路分组，不需要额外读取其他作品。Emby、本地或其他未提供分组的来源继续显示现有队列和可用版本，不在播放器解析来源私有上下文。

线路点击仅切换浏览的集数，不中断播放；点选具体集数才调用 Resolver。这样即使两个网盘的文件名和分集名不同，也能查看和选择该线路实际存在的条目。直接切换版本的旧入口仍保留。

切换时使用请求副本，Provider 修改请求或解析失败不会提前改变当前线路；身份校验、历史保存和会话提交完成后再关闭面板。失败在面板内显示错误，保留当前媒体；请求期间禁止重复选集。仅允许当前来源的合法队列项，迟到响应、页面退出和会话失效不能继续提交。成功选择另一线路后，前后集使用该线路队列。

面板打开期间阻断视频手势并暂停控制栏自动隐藏；关闭后恢复。返回键先关闭选集，再处理退出全屏；点击当前集仅关闭面板，不重启媒体。弹窗代次保护避免旧关闭回调误关新面板。

## 验证

293 项相关测试通过，覆盖目录/详情/搜索兼容、完整线路分组、异名分集切换、队列提交、失败保留、请求序列化、显示倒序、来源身份、原生弹窗参数、生命周期和材质厚度/降级。ArkTS 编译、应用打包和签名通过。

没有自动安装或调试设备。触控、真实视频背后的折射/反色、横竖屏实际排版仍需设备验证。本次没有修改来源代理、网盘登录或修复日志中的夸克代理 HTTP 500。

## 官方依据

- [组件适配沉浸光感](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-component-adaptation)
- [自定义弹窗](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-methods-custom-dialog-box)
- [通用 systemMaterial](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-universal-attributes-image-effect)
