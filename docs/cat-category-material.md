# 猫源首页搜索与分类栏

## 当前样式：参考 Kazumi 时间表

2026-10-22重新从用户指定仓库的main读取[TimelinePage](https://github.com/2759720161/Kazumi/blob/main/entry/src/main/ets/pages/timeline/TimelinePage.ets)、[TopicTagButton](https://github.com/2759720161/Kazumi/blob/main/entry/src/main/ets/components/recommend/TopicTagButton.ets)及[ImmersiveMaterial](https://github.com/2759720161/Kazumi/blob/main/entry/src/main/ets/utils/ImmersiveMaterial.ets)，文件快照保存在tmp/kazumi-timeline-reference。当前时间表使用TopicTagButton；旧的本地参考副本中每项内嵌HdsTabs的实现不再是联网读取的版本。参考特征为30vp胶囊、13号文字、左右12vp内边距、选中加粗、8vp项间距，以及不附加materialColor、不使用投影的原生交互光感。

猫源分类项据此调整为30vp视觉高度、15vp圆角、最小52vp宽，文字13号。根据用户随后要求开启阴影与反色，文字改用官方反色白名单中的sys.color.font_primary与sys.color.font_emphasize（默认强调蓝色）；满足系统条件时允许随材质反色。最新要求是仅用字色区分选中态，因此字重统一为Medium，删除浅色／深色主题的选中蓝色背景，普通和选中态使用相同回退底色；原生材质开启时两者均透明，不附加选中赋色。选中颜色使用250ms弹簧属性动画；不动画化宽度、内边距或列表内容。44vp外层布局与显式44vp触摸热区保留了点击空间；没有额外的父级点击事件，仍由原生Toggle处理一次选择。

原生材质不设置materialColor，避免固定赋色背板削弱设置页五档材质厚度的差异；当前applyShadow与colorInvert均为true，interactive和lightEffect保留。此调整替代下方历史记录中的赋色／阴影方案。自动反色是否触发还受设备能力、系统光感强弱及材质厚度影响，并非任何设备、任何厚度均会反色，不强制修改用户厚度。继续使用ToggleType.Button，原因是官方FAQ明确它的材质可在内容区全页面生效；没有直接照搬参考项目的普通Button。关闭或不支持原生材质时仍恢复浅色／深色主题的普通和选中背景。

分类栏仍为唯一的ListItemGroup吸顶header，横向隐藏滚动条；项间距8vp，外侧效果留白4vp。材质厚度从设置页的immersiveMaterialStyle通过StorageLink和Prop实时传入。点击当前分类不取消、不重复请求、加载中禁止切换和旧帧回调隔离均保留。

243项既有回归测试通过，原生配置测试更新为核对五档厚度、无固定赋色、启用投影与反色。未自动安装或调试设备，本地测试无法确认手机上的实际通透、光感、点击热区与吸顶绘制。

## 返回首页保留浏览状态

2026-10-22修复从服务、设置或详情页返回时无条件重新请求猫源首页的问题。CatVodContent的激活回调不再直接刷新目录、分类和第一页，也不在普通失活时递增请求代数、清除加载状态。已发起的首页及分页请求可以在组件仍存活但不可见时完成；隐藏期间不向首页标题发布导航状态，返回后重新发布当前目录和背景。

首次激活及明确的刷新使用refreshPending区分；隐藏时收到的刷新信号延迟到重新激活处理。已加载的分类、视频、页码、轮播数组及版本、背景与Scroller继续沿用，不因底部页签切换而重置。内容为空也是成功加载，不以视频数量判断是否需要重试。真实组件移除仍作废旧请求；若当时有整页加载未完成，下次出现重新加载，防止永久停留在加载中。更换目录和订阅配置继续通过原有source.id加updatedAt的父级ForEach键重建内容，不把旧来源的数据跨配置复用。

重新激活仅独立更新观看记录，使用内容请求代数与观看记录请求序号双重保护，旧历史响应不能覆盖较新历史，历史失败不覆盖首页内容错误或触发整页刷新。原生轮播本身继续根据isActive暂停／恢复，没有改动轮播样式、阴影、反色或材质厚度。

新增12项真实处理方法回归，覆盖反复切页、首次隐藏、加载中切页、分页中切页、隐藏时刷新、分类切换、失败保留与重试、旧内容请求与旧历史响应隔离、空内容和保留实例再次出现。测试使用受控数据，不代替设备上的实际切页及滚动位置验证。

## 首次显示材质与渲染阶段通知修正

读取2026-10-22 19:27:27保存的log.txt（233199字节，1328行）。19:27:08.618设备记录sdk=26、supported=true、应用state=1、设备材质等级GENTLE和ultraThin厚度；19:27:08.626及19:27:12.300已分别记录选中／普通分类的native_configured_clear_not_render_confirmation。因此不能将首次看不到效果解释为未执行材质接口或设备不支持。现有日志没有逐节点绘制结果，无法单凭日志证明背景覆盖是唯一原因。

代码检查发现CatVodCategoryTab的链式backgroundColor、selectedColor与CategoryTabMaterialModifier重复拥有相同属性。官方AttributeModifier指南明确提醒避免同时设置相同属性，以免刷新时修饰器不生效。现在组件只保留修饰器入口，由修饰器唯一管理普通／选中底色、enabled和systemMaterial；selectionEnabled作为修饰器参数，使加载结束时在启用按钮后重新应用透明原生材质，而不依赖切换底部页面触发额外更新。日志增加enabled维度，仍去重，不输出来源URL或用户搜索词。

日志19:27:18.795另有明确的HomePage.catNavigation在渲染期间变更错误，来自内容激活回调同步通知父级的路径。导航通知改用UIContext.postFrameCallback合并到下一帧，读取最新导航数据，离页／销毁使旧回调失效。轮播连续取色仍保留原有同步回调，没有把每帧背景颜色更新整体延迟，也没有恢复切页整页加载。

新增回归覆盖加载禁用到启用的材质重配顺序、父级渲染期间不发布导航、同帧通知合并读取最新状态，以及离页旧帧不能覆盖重新激活的通知。原有阴影、自动反色、仅字色选中态、材质厚度、分类吸顶和首页状态保留继续沿用。测试与接口配置不能证明目标设备实际绘制结果；未自动安装或调试设备。

## 跨应用启动的首页缓存

CatHomeCache通过现有PreferencesStore的严格读写与flush持久化目录名称／搜索能力、分类和第一页的展示元数据；重启进程后可直接恢复。首页总览的缓存身份为来源id、类型、updatedAt、完整configJson的SHA256；各分类另外加入分类id，保留旧版总览键的兼容性。配置原文不作为键保存，订阅、目录、账号或配置修订不同不会误用同一条缓存。总览与已访问分类分别保存首屏，不缓存搜索结果、播放地址、分集道路和site.ext。观看记录仍从本地历史独立读取。

有效期6小时：命中时直接构建本地Provider会话，不调用ProviderRegistry、sites、categories或第一页请求。超过6小时先显示快照，再在后台原子读取完整的目录／分类／第一页，成功后替换并保存；失败不混入半份新目录，不清空旧首页，提示保留已有内容。最多保留7天的过期快照。目录标题下拉菜单末尾增加“刷新当前目录”，显式刷新绕过缓存；首页已有内容时刷新保留当前展示，失败继续保留。

CatNode封面可能是上一次进程的127.0.0.1随机端口，不能直接复用该地址。恢复时暂不请求旧端口，在确需代理封面的情况下启动本地运行环境，再将封面路径绑定到本次端口，并保留原视频身份。此过程不重新请求目录和首页，但运行环境可能进行订阅MD5检查，封面图片仍按需加载；本次不是离线图片下载功能。无本地代理封面的缓存命中不为首页主动启动Node。观看记录中的本地代理图片同样重绑。

2026-10-22补充修复：原海报列表仅以作品id作为ForEach键，缓存恢复后即使poster由空串更新为本次代理地址，也可能保留旧组件绑定。现以id、poster、标题、备注共同确定展示键，按官方ForEach规则在展示内容变化时重建卡片；键生成器接收但不使用index，避免隐式索引键。代理完成后的状态判断改用首屏内容修订号与请求代数，不依赖ArkUI观察数组的引用相等。代理准备与过期刷新独立发起，分页追加不会被图片恢复覆盖；未完成的准备在保留页面重新出现时续接。新增CatHomeCache日志区分restore_hit／miss、artwork_prepare_begin／done／failed，不输出订阅配置与封面地址；done表示地址已绑定，不表示设备图片已经绘制。

总览和分类都从各自第一页按原顺序选择最多6张有效海报作为轮播，分页追加不改变轮播；搜索结果不显示轮播。仍使用同一个3D海报转盘及取色组件。分类tab的尺寸、选中效果、吸顶与沉浸光感组件及材质适配器保持原样。

存储队列防止同时写入不同来源时相互覆盖，最多8份快照、总序列化文本不超过1Mi字符；每份最多200条视频、200个分类、500个目录。淘汰时先移除较旧分类快照，优先保留冷启动总览及本次写入；极限容量下总览也可能被淘汰。超过条数上限的快照明确标为不完整，命中后必须后台更新，避免裁剪内容在6小时内被误当成完整首页。缓存损坏、存储读取失败、未来时间异常、超出大小或保留期限的缓存均不会阻断正常加载。缓存写入先捕获独立展示数据，避免后续分页或分类变化污染已经发起的写入。旧读取／代理启动结果受组件生命周期和请求代数保护，不覆盖已切换的页面。

回归增加真实缓存读写的重启实例恢复、6小时边界、7天保留、配置隔离、并发与容量控制、敏感扩展／播放数据剔除、存储失败恢复、代理地址重绑，以及首页冷启动命中、过期成功／失败、主动刷新和目录菜单入口。测试使用本地受控存储与网络替身，未自动安装或调试设备。

## 此前实现记录

2026-10-22：首页卡片按压参考Kazumi的RecommendCard，采用0.98缩放与150ms过渡；猫源首页海报和继续观看启用仅缩放反馈，去掉按钮默认按压叠色与卡片压暗，轮播卡片改用同样的显式缩放。点击、滚动、取消触摸和原有轮播运动继续沿用。根据用户补充“分类tab不做改动”，分类组件及CategoryTabMaterialModifier保持此次修改前的配置，包括已有原生阴影、反色、形变和点光源；本次按压调整没有用于分类tab。

2026-10-22：CatVodContent 在嵌入首页（embeddedHomeTitle=true）时不再渲染搜索框；推荐、动作片等分类栏直接位于轮播下方。首页右上角搜索现与 Emby 统一进入 [独立影视搜索页](media-search.md)，不展示浏览分类。CatVodBrowserPage 继续保留给独立来源浏览，仍有搜索框、结果清除与分页，同样使用这里的分类项及吸顶布局。

分类项继续使用ToggleType.Button。官方[沉浸光感FAQ](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-faq)明确Toggle可在全页面生效，不需要把分类栏搬入Navigation标题栏；ChipGroup自身的API参考又要求材质位于标题栏或底部TabBar，因此未将内容区分类直接改为ChipGroup。不同组件的生效范围不能混用。

2026-10-22针对用户反馈“没有通透和光感，吸顶后部分文字不可见”，分类项改用独立CategoryTabMaterialModifier，不修改其他播放／详情按钮。原实现将普通与选中背景同时清空，并在薄材质时依赖自动反色；没有最新设备渲染日志，不能断言这是唯一原因，但此配置缺少稳定的文字／背板对比保障。本次在原生ImmersiveMaterial中设置带透明度的materialColor，普通和选中状态分别使用主题赋色，保留interactive、lightEffect和原生阴影。文字改用配套的应用主题颜色，选中仍为蓝色，并关闭分类项的自动反色，避免吸顶后文字随滚动图像反复翻色。

依据官方[ImmersiveOptions](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-uimaterial#immersiveoptions)，materialColor可为材质混合半透明颜色，纯不透明颜色会遮挡材质滤镜；colorInvert只对指定资源及满足条件的薄材质生效，不能作为所有设备上的对比度保障。本实现不在分类栏外层叠加通用材质、背景模糊、假高光或额外渐变；一项只有一个原生材质。

适配器首先建立普通／选中回退背景；API23–25不访问新材质接口。API26检查apiAvailable、设备支持与MaterialState，关闭或不支持时用Material.empty显式移除旧材质并恢复主题背景。材质厚度仍跟随immersiveMaterialStyle，不强制修改用户设置。每项高44 vp、圆角22 vp，横向容器四周留白由4 vp增至8 vp，给吸顶布局中的阴影及交互形变留出空间。

日志按SDK、材质结果、厚度及选中状态去重，区分native_configured_tinted_not_render_confirmation、fallback_old_api、fallback_unavailable_api和fallback_disabled_or_unsupported；不在滚动帧重复输出。日志表示接口配置结果，不等同于真机绘制成功。

父页面的 categoryId 是单选状态的唯一来源。点击当前项不发起分类请求；快速重复的原生事件在同一个待恢复帧内只处理一次。原生双向状态先渲染，再通过现有项目同样使用的 FrameCallback 恢复父级最新状态，避免同一帧内切回原值导致原生控件与业务状态不一致。离页或重新进入后，旧帧回调不能覆盖新组件状态；加载中也拒绝晚到的选择事件。

本地测试覆盖当前项不取消、父级拒绝或接受选择、延迟更新、加载禁用、重复事件以及离页旧回调隔离；继续运行已有的材质版本保护、能力降级、五种厚度与系统关闭用例，以及两页轮播和背景同步回归。未进行设备自动安装或调试；测试中的帧与原生接口使用替身，不能作为实际材质绘制或光感效果的确认。

本轮 134 项本地测试通过，编译、打包、签名及 ZIP 完整性检查通过。安装包为 entry-cat-tabs-material-debug-signed.hap，SHA256 为 8c72de593c2294805574e28112310ea067041c178d4bcb821ff06e4b15eac4fb。包内包含新分类组件、原有轮播与整图取色实现；签名配置、Node 运行库及猫源宿主脚本未变，证据记录为 tmp/cat-tabs-material-evidence.json。

## 上滑吸附到标题栏下方

同日根据用户截图，纵向浏览容器由 Scroll 改为 List，将原分类横向 Scroll 放进 ListItemGroup 的 header，并启用 StickyStyle.Header。分类栏在自然位置时跟随内容滚动，上滑抵达标题栏下方后由原生列表固定，下滑回到原位置时恢复。只保留一份横向分类组件，不通过两份控件切换或逐帧移动复制的浮层，分类横向位置及选中状态继续沿用。

List 的 contentStartOffset 使用 getTopSpacerHeight(topSafeHeight)，与项目既有顶部安全区和 MINI 标题栏间距一致。公开 [ListItemGroupLayoutAlgorithm::LayoutHeaderFooterLTR 实现](https://github.com/openharmony/arkui_ace_engine/blob/master/frameworks/core/components_ng/pattern/list/list_item_group_layout_algorithm.cpp) 以 contentStartOffset 计算 Header 的固定位置；这属于公开引擎依据，不代表已取得手机系统所用的精确源码版本。接口及最低版本以官方 [List](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-list) 和 [ListItemGroup](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-listitemgroup) 文档核对，均低于项目 API 23 下限，不使用 API 26 新增的 headerStyle。

顶部偏移统一由列表提供，轮播的 topInset 改为 0，避免将标题间距累计两次。轮播后 20 vp、无轮播时顶部 12 vp、分类后 24 vp 的间距继续保留。独立浏览页的来源标题和搜索框放在分类前方，仍可随内容滚走。底部安全留白仍位于内容内，横向分类本身保持透明，保留此前的组件级材质。既有父页面 Scroller 继续绑定唯一的纵向 List，标题栏滚动联动、分类切换回顶、搜索和分页的业务方法不变。

本轮复用的 134 项回归测试全部通过，编译、打包与签名通过；本次布局调整未新增模拟原生吸顶算法的单元测试。测试不能代替设备上的吸附位置、横纵手势与材质绘制检查，按用户要求未进行设备自动安装或调试。

吸顶版安装包为 entry-cat-tabs-sticky-debug-signed.hap，SHA256 为 f9183f296081ae07233c62023ccc38bce1d62a5acbac26449f6ab20ea61dc0de，ZIP 完整性检查通过。包内新增布局方法已核对；签名配置、Node 运行库及三份猫源许可／宿主文件与上一版一致，核验记录为 tmp/cat-tabs-sticky-evidence.json。

## 本次验证与安装包

243项本地回归通过，新增覆盖分类普通／选中赋色、五种厚度、固定文字反色策略、原生光感参数、运行时关闭后清除旧材质和恢复背景、旧API零访问。编译、打包和签名通过。没有进行设备自动安装或调试；背景真实通透度、吸顶文字与光感仍需设备确认。

安装包entry-cat-tab-light-fix-debug-signed.hap，核验记录tmp/cat-tab-light-fix-evidence.json。既有双胶囊搜索、聚合范围、统一菜单、分类吸顶与轮播均保留，签名配置与Node运行库不变。

## 初始分类加载

2026-10-22：初始分类数据与首页缓存尚未就绪时，不创建单独的“推荐”（CatNode）或“全部”（CatVod）占位tab，也不保留空的横向Scroll。首屏数据或分类就绪后显示正常分类栏；缓存命中和已有分类的切换／刷新继续保留可用分类。现有分类组件的材质、选中文字颜色、吸顶布局均不调整。构建与包校验记录见tmp/cat-tabs-initial-loading-evidence.json。

同日移除LoadingGrid及六张海报／标题骨架。loading状态改为页面根Stack上方的全尺寸Column居中放置PageLoadingState，统一显示转圈和“正在读取作品”，不再随列表内容出现在顶部。保留原纵向List和Scroller绑定，已有分类在分类请求期间继续显示；后台保留内容刷新和分页仍沿用原状态，不显示全页加载提示。此次不调整详情页、分类材质、轮播或缓存服务。核验记录见tmp/cat-home-centered-loading-evidence.json。
