# 猫源首页自动分页

2026-10-22：猫源首页、分类及独立猫源浏览页共用的CatVodContent移除底部“加载更多”按钮，改为接近底部自动追加下一页。搜索结果页的独立分页控件不在本轮范围。

## 触发与保护

- 原生List的onDidScroll、onReachEnd，以及列表／内容区域尺寸变化触发检查。数据加载完成、缓存首屏恢复和页面重新激活时也检查一次。
- 每帧合并检查，通过Scroller.getItemRect(1)读取分类／影片分组在List内的矩形；其底部距离可视区域底部不超过max(240 vp, 半屏高度)时加载下一页。不是用List的末尾索引判断，因为当前影片网格位于同一个ListItemGroup内。
- 不满一屏或预加载范围的短页，在新内容完成布局后继续检查；随着列表增长离开阈值即停止，不使用定时轮询。
- 首屏未完成、刷新中、分页中、末页、空列表、非活动页面、页面销毁或Provider尚未就绪时不发起自动分页；不可用、非有限值或零高度的原生几何信息直接忽略，等待下一次布局／滚动事件。
- 一次只请求一页。检查帧和网络响应都有生命周期／请求代数保护，换分类、离页后旧回调不能追加到新页面。
- 请求失败保留已有海报，在底部显示错误和“重试”。自动检查在错误状态下停止；明确重试成功后恢复自动加载。
- 下一页为空，或只包含已经显示的作品id时，将该页作为末页，防止错误pageCount导致持续空请求。服务端忽略请求页码的情况仍保留原错误检查。

底部只保留分页进度、错误重试和“已经到底了”等现有末尾状态。分类tab、吸顶材质、轮播投影、点击时长及首屏快照缓存保持原样。缓存仍只保存各分类第一页，自动追加页不扩大持久化范围。

## 依据与验证

接口依据为官方[List](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-list)、[Scroller.getItemRect](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-scroll#getitemrect11)及[onDidScroll](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-scrollable-common#ondidscroll12)，均低于项目API23下限。

本地回归使用实际生命周期／分页处理方法及受控原生几何数据，覆盖阈值边界、帧合并、请求串行、短页补充、失败停止与明确重试、隐藏／换分类的旧回调隔离、无效几何恢复、空页及重复页终止，同时验证分页不重置轮播与滚动位置。

未自动安装或调试设备；本地测试不代表实际设备上的预加载距离、网络时延或原生布局测量已验证。结果记录在tmp/cat-auto-paging-evidence.json。
