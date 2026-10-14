本地工作台与自制工具的 macOS 测试安装包。

| 文件 | 应用 | 适用系统 |
| --- | --- | --- |
| LocalWorkbench-2.1.1-macOS-arm64.dmg | 本地工作台，内置运行环境 | Apple Silicon，macOS 14+ |
| PhotoPin-1.0-macOS-arm64.dmg | 照片置顶，图片悬浮、锁定和缩放 | Apple Silicon，macOS 12+ |
| FrameRecorder-1.1-macOS-arm64.dmg | 框录，区域截图与录屏，独立声音开关 | Apple Silicon，macOS 15+ |

打开 DMG，将应用拖入 Applications。工作台不需要另外安装 Python。安装照片置顶和框录后自动识别，无需填写路径。未包含作者个人配置、第三方软件或模型。

本次为 ad-hoc 签名、未经 Apple 公证的测试版，首次打开可能被系统拦截。核对下载来源后，由你在「系统设置 → 隐私与安全性」允许本次打开。无需关闭 Gatekeeper。框录需要手动授权屏幕录制和麦克风。

最低系统版本经编译目标与依赖检查，实际运行环境为 macOS 26 Apple Silicon；尚未在每个旧系统实测。工作台已验证内置运行环境启动与页面资源，三个 DMG 均挂载检查并通过代码签名完整性验证。SHA256SUMS.txt 提供文件校验值。

Intel Mac、Windows/Linux 暂无本次二进制包。工作台可使用仓库中的源码部署方式。
