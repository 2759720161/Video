# MPV 播放诊断与猫源缓存传输

2026-10-24。对照 log.txt 与参考日志.txt：当前样本在 2.033 秒内完成续播准备，随后 MPV 打开直连流 15 秒超时；同一地址切换系统播放器约 1.5 秒后正常播放。参考样本使用来源本地代理，MPV 成功播放。两者媒体规格不同，不能据此确定直连、代理或解码中的哪一项是唯一根因。

## 改动

1. 对带自包含 pst 票据的缓存保存来源代理相对路径，重启后绑定当前运行期端口并验证。优先保留来源传输行为；不支持恢复时验证直连，两者失败再走正常来源解析。普通直连和不完整本地代理保持原有边界。详见 cat-playback-stream-cache.md。
2. 原生 MPV 事件桥把日志订阅由 info 改成 terminal-default，使选定模块的 debug 信息能进入事件回调。ArkTS 配置仅打开播放器、流、FFmpeg、解封装和解码相关模块，其他模块为 warn。项目随库 client.h 和 mpv 官方 client.h 均记录 terminal-default 的语义：遵循 msg-level，而非固定在 info 层过滤掉 debug。
3. MpvDiagnostic 只输出预定义字段：network/demux/decoder/video_output/player 阶段、HTTP 状态码、Range 数字范围、连接/TLS/超时/权限/失败/打开/跳转/硬解/视频输出事件。未知文本不原样写日志，不输出 URL、票据、Cookie、Authorization 或服务端响应正文。
4. 每次 prepare 重置计数，普通诊断最多 256 条，错误最多用到总共 272 条。超时记录 nativeMessages 与 lastStage；零条原生消息只能说明没有收到日志，不能据此判定网络或解码原因。

## 观察字段

- stream_cache status=hit transport=source_proxy：恢复的是当前运行期代理，不是旧端口。
- stream_cache status=proxy_probe_failed：当前代理没有通过小范围媒体验证，将尝试已缓存上游直连。
- stream_cache status=hit transport=direct：普通直连、旧格式缓存，或代理恢复失败后的已验证直连。
- mpv_diag ... stage=network http_status=403：MPV 网络层收到权限错误；需结合刷新日志判定后续行为。
- mpv_diag ... event=seek / range=...：出现寻址或范围请求，不能单凭该事件认定已经成功读取。
- mpv_diag timeout ... nativeMessages=... lastStage=...：超时时最近收到的诊断模块；不是精确的阻塞栈。

本轮没有改短超时、强制替换用户内核、修改轮播和分类 tab，也没有自动安装或调试设备。代理恢复与 MPV 首帧是否改善仍需用户在同一资源、同一线路上复测。旧缓存没有保存过的相对代理路径无法从上游 URL 反推出，须重新成功解析该资源一次。

官方 API 参考：https://raw.githubusercontent.com/mpv-player/mpv/master/include/mpv/client.h
