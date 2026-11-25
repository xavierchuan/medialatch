# MediaLatch

MediaLatch 是一个 macOS 原生媒体下载器。粘贴公开链接或整段分享文案，即可解析并保存你拥有或获准下载的媒体。

- 下载 MP4、MKV 视频，或提取 M4A、MP3、WAV、FLAC 音频。
- 在 App 内预览视频、复制投稿文案和保存封面。B 站有可用备用地址时会显示备用源。
- 查看进度、取消或重试任务，完成后可在访达查看文件。
- 小红书公开图文页面返回图片时，可按原顺序批量保存。抖音和小红书本地解析失败时，可选择通过 dyxhsdownloader.com 网页解析。打开网页前，App 会提示该服务将收到分享链接。小红书视频和多图笔记的真实下载仍待验证，实际可用性取决于平台和第三方服务的响应。

## 从源码运行

需要 macOS 14 或更高版本、Xcode 或命令行工具，以及本机安装的 FFmpeg。安装 Node.js 可为需要 JavaScript 解析的站点提供运行环境。

```bash
git clone https://github.com/xavierchuan/medialatch.git
cd medialatch
brew install ffmpeg node
swift test
zsh scripts/package_app.sh
open dist/MediaLatch.app
```

打包脚本从 yt-dlp 官方发行版下载并校验下载组件。App 和本地 ZIP 都生成在 `dist/` 下。脚本默认构建 Apple Silicon 和 Intel 通用版本，也可以用 `MEDIALATCH_BUILD_MODE=native zsh scripts/package_app.sh` 只构建当前架构。本地包使用 ad-hoc 签名，适合在构建它的 Mac 上运行。

## Codex 插件

自动化插件维护在 [MediaLatch for Codex](https://github.com/xavierchuan/medialatch-codex)。

## 许可证

源码按 [MIT License](LICENSE) 发布。MediaLatch 调用 [yt-dlp](https://github.com/yt-dlp/yt-dlp) 和本机的 [FFmpeg](https://ffmpeg.org/)。第三方组件遵循各自的许可证。
