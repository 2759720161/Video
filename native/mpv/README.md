# mpv for HarmonyOS

这是 Video 项目正式维护的 mpv HarmonyOS 移植模块。项目构建只读取本目录，
不依赖根目录的 `mpv-master` 或 `新建文件夹` 参考工程。

## 目录

- `src/`：带 HarmonyOS EGL/OpenGL、OHCodec 和 OHAudio 支持的 mpv 源码。
- `ffmpeg-src/`：带 OHCodec、P010/Main10 和字幕 demuxer 修复的 FFmpeg 源码。
- `prebuilt/ffmpeg/`：构建 mpv 使用的 FFmpeg 静态库与头文件（本地生成，不提交）。
- `prebuilt/deps/`：libass、FreeType、FriBidi、HarfBuzz、mbedTLS 等依赖（需在本地准备，不提交）。
- `dist/`：应用直接链接并打包的 mpv SDK。
- `scripts/`：WSL 下使用 DevEco Studio NDK 的可重建脚本。
- `legacy/`：迁移前未被 HAP 使用的旧 SONAME 兼容库，仅作追溯。

## 构建

在 WSL 中执行：

```bash
bash native/mpv/scripts/build_all_ohos.sh ~/ohos_ndk
```

输出库为 `dist/lib/arm64-v8a/libmpv.so`。应用的 CMake 会从该根目录模块
读取头文件和动态库，不再从 `entry/src/main/cpp` 保存另一份 mpv SDK。
普通应用构建只依赖仓库中已提交的 `dist/`，无需准备 `prebuilt/`；只有重新
编译 FFmpeg 或 mpv 时才需要本地预编译依赖。

应用内 m3u8 转 MP4 使用 mpv 的编码输出，重编译时需先运行
`scripts/build_ffmpeg_ohos.sh`，该脚本会启用 OpenHarmony H.264 视频编码器；随后再运行
`scripts/build_libmpv_ohos.sh` 更新 `dist/` 中的运行库。

## 已集成功能

- HarmonyOS XComponent / EGL / OpenGL GPU 输出
- OHCodec H.264、HEVC 硬件解码及 copy-back 字幕合成
- 10-bit HEVC P010 正确识别和按字节跨度拷贝
- ASS/SSA、SRT、WebVTT 外挂字幕和 libass 特效
- OHAudio 音频输出
