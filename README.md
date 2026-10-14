# 本地工作台 · Local Workbench

把常用应用、网页和项目目录放在一个本地页面里。工具留在原位置，工作台负责整理和打开。

不需要 Node.js、npm、数据库、Docker 或 API Key。运行时只依赖 Python 标准库；前端资源全部本地提供。

![工作台预览](docs/preview.png)

## 下载安装包

[前往 GitHub Releases 下载](https://github.com/Tyler9169/local-workbench/releases/tag/v2.2.1)，或点击工作台左下角「下载安装包」。

| 应用 | 平台 | 系统要求 |
| --- | --- | --- |
| 本地工作台 2.2.1 | Apple Silicon Mac | macOS 14+ |
| 照片置顶 1.1.0 | Apple Silicon Mac | macOS 12+ |
| 框录 1.2.0 | Apple Silicon Mac | macOS 15+ |

打开 DMG，将应用拖入 Applications。工作台安装包内置 Python，无需另装运行环境；数据保存在 `~/Library/Application Support/LocalWorkbench`。通过菜单栏打开页面或退出服务。

这些是未经过 Apple 开发者签名、公证的测试版。首次打开可能被系统拦截，请核对来源后在「系统设置 → 隐私与安全性」允许本次打开。框录需要用户手动授权屏幕录制，开启麦克风时需要麦克风授权。Intel Mac、Windows 和 Linux 暂无二进制安装包；工作台可继续通过下方源码部署。

工作台自动识别 `/Applications` 和 `~/Applications` 中的照片置顶、框录，每 10 秒及切回页面时检查，无需填写路径。应用按 bundle ID 识别，改名仍可发现；两处都有安装时优先用户 Applications，已有同一应用入口不会重复显示。其他工具仍可手动添加。最低系统版本依据编译目标和依赖检查，实际运行验证在 macOS 26 的 Apple Silicon Mac 上完成，尚未逐一测试旧系统。

## 快速开始

安装 Python 3.10 或更新版本，然后下载本仓库 ZIP 并解压，或运行：

```sh
git clone https://github.com/Tyler9169/local-workbench.git
cd local-workbench
python3 server.py
```

浏览器会自动打开 **http://127.0.0.1:43120**。点击「添加工具」，填写名称、类型、路径或网址即可。初次启动会识别已安装的照片置顶和框录，不附带作者的个人工具和路径。

- macOS：也可双击 `start.command`；如果没有执行权限，先运行 `chmod +x start.command`。
- Windows：安装 Python 后双击 `start.bat`，或运行 `py -3 server.py`。
- Linux 桌面：运行 `./start.sh`；打开目录需要系统提供 `xdg-open`。
- 停止：在启动终端按 **Ctrl+C**。关闭浏览器页面不会停止服务。

端口被占用时：

```sh
python3 server.py --port 43125
```

不自动打开浏览器：`python3 server.py --no-open`。不要同时启动多个进程共用同一配置目录。

## 可以做什么

- 网页内添加、编辑、移除入口；移除入口不删除原应用或文件。
- 分类、关键词搜索、浏览器本地收藏；快速入口优先显示收藏。
- 检查本地目录是否存在；移动或断开磁盘后保留入口并提示修正路径。
- macOS `.app` 应用、任意本地目录、HTTPS 网页、本机 HTTP 服务链接。
- 支持 `~/Documents/...`，不需要写死用户名。

**边界：** 本地服务必须自行启动；工作台不会执行自定义 shell 命令、安装工具或复制工具本体。Windows/Linux 当前支持网页和目录，不支持添加可执行程序。网页入口不做联网健康检查。“位置可用”仅表示目录存在，不代表对应软件的所有功能正常。

## 数据与迁移

工具清单保存于 `data/tools.json`，首次保存入口时自动创建。数据目录已被 `.gitignore` 排除；不要将个人工具配置提交到公开仓库。收藏保存在当前浏览器的 localStorage，不会跟随清单迁移；更换端口或浏览器会使用独立收藏。

备份/迁移时复制 `data/tools.json`，再通过页面调整新电脑上的路径。也可参考 `tools.example.json` 手工配置；支持 `url`、`folder`、`app` 三种类型。编号须唯一，分类为日常工具、影音创作、开发分析、资讯灵感之一。最多 200 个入口。

自定义数据目录（例如升级时保持数据独立）：

```sh
WORKBENCH_DATA_DIR="$HOME/.local-workbench" python3 server.py
```

Windows PowerShell：

```powershell
$env:WORKBENCH_DATA_DIR = "$HOME\.local-workbench"
py -3 server.py
```

升级时替换程序文件，保留自己的 `data` 目录。配置损坏时页面显示错误，写操作不会覆盖损坏原件；请恢复备份或修复 JSON。

## 既有个人工作台集成

可选的 `data/integration.py` 用于连接自己已有的固定启动器。它是你信任并手工放置的本地 Python 代码，启动时加载；网页不能上传或修改它。此文件与个人数据一样不会提交到仓库。

接口：`tools()` 返回带 `managed: true` 的工具卡片列表；`action(id, verb)` 校验工具编号和允许的操作后，调用原启动器并返回提示。集成入口在原配置中管理，网页只提供打开操作。普通部署无需此文件，不会执行任何集成代码。

## 本机访问与隐私

仅监听 `127.0.0.1`，并校验 Host、Origin 和自定义请求头。静态资源使用固定白名单，配置文件不能通过 HTTP 下载。启动操作只接受已登记入口，不接收命令或额外参数；所有页面文本均转义。

不提供遥测或云端同步。点击网页入口会通过默认浏览器访问该网站。网址不允许账号密码、查询参数和片段，避免把带令牌的登录链接写进配置。

这是单用户桌面工具，没有远程鉴权。**不要通过反向代理、公网隧道或修改监听地址暴露到网络。** 不建议 Docker 部署：容器无法直接打开宿主机应用和文件管理器。

## 开发与验证

```sh
python3 -m unittest discover -s tests -v
# 可选：需要 Node.js，仅用于开发语法检查
node --check dist/app.js
```

`server.py` 负责配置、校验及系统打开；`dist/` 是无需构建的 HTML/CSS/JavaScript。GitHub Actions 在 macOS、Windows、Linux 上运行配置/API 测试；真实系统打开行为仍需在对应桌面环境验证。

本机已验证 macOS 的页面增删改与目录打开流程。跨平台 CI 结果以仓库 Actions 为准。

## 许可

MIT。欢迎按自己的工作流修改与分享。

## 构建 macOS 安装包

需要 Xcode Command Line Tools 和构建用 Python。

```sh
python3 -m venv .venv-build
.venv-build/bin/python -m pip install pyinstaller==6.16.0
./packaging/build-macos.sh
zsh tools/photopin/build.sh
zsh tools/framerecorder/build.sh
./packaging/package-tools.sh
```

构建产物位于 `releases/`，不进入 Git；通过 GitHub Releases 分发。应用运行数据不会被打包。自制工具源代码位于 `tools/`。

## 检查更新与一键更新

工作台左下角点击「检查更新」，发现新版本后点击「一键更新」。更新清单来自本仓库的 `update.json`，无需 GitHub 账号。当前也会提供测试版更新，面板会明确标注。

更新器只从本仓库 Releases 下载对应的运行文件，校验 SHA256、文件清单与兼容版本，再用独立进程检查新版本能否读取现有配置。更新前备份工具清单、本机集成配置和当前浏览器收藏，随后切换运行版本并自动重启。下载、校验或启动预检失败时不会切换版本；重启调用失败会恢复原版本指针。

个人数据仍留在原数据目录，更新文件位于其中的 `updates/versions`，备份位于 `updates/backups`，不会覆盖 `tools.json`、`integration.py` 或原应用。访问地址不变时，浏览器收藏继续保留。源码部署的工作目录和未提交文件也不会被自动更新覆盖。

此功能更新工作台运行代码与界面，不替换照片置顶、框录或系统权限。需要升级原生启动器、Python 运行环境或更新协议时，会提示下载新安装包。更新包的 SHA256 用于完整性检查；发布仍依赖 GitHub 仓库和 HTTPS，并非 Apple 公证。

发布流程：先运行测试和 `packaging/build-macos.sh`，再运行 `python3 packaging/build-runtime.py`；上传 DMG、runtime ZIP 与 SHA256SUMS 后，最后修改 `update.json` 指向已发布版本。


### 照片置顶与框录更新

照片置顶：点击 macOS 菜单栏的「照片置顶 → 检查更新…」。框录：控制面板或菜单栏图标中的「检查更新…」。发现新版后点「一键更新」，完成后自动重新打开；录制或导出期间不安装更新。

两个应用从本仓库 `native-updates.json` 检查版本，从 GitHub Releases 下载专用 ZIP，验证 SHA-256、包标识、版本和代码签名。更新在原位置替换程序，保留 `local.tyler.photopin` / `local.tyler.framerecorder` 的 UserDefaults 和照片、录屏文件；备份设置保存在 `~/Library/Application Support/<Bundle ID>/Updates/`，旧应用保存在原安装位置旁的 `.backup-<UUID>` 路径。新版本 60 秒内未完成启动时恢复旧版，失败版本保留供排查。应用需放在当前用户可写的位置，不能直接从 DMG 或 App Translocation 中更新。

照片置顶保留照片路径、锁定状态和窗口位置，并从此版开始保存缩放比例。框录保留两个声音开关，并从此版开始保存帧率、鼠标指针选项。更新不清理任何 macOS 权限记录，也不重新签名下载的应用。

当前发布包使用 ad-hoc 签名，**无法保证屏幕和麦克风授权跨版本保留**。Apple 的 [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) 说明 ad-hoc 的身份要求绑定具体代码版本。正式发布应设置同一个 `CODE_SIGN_IDENTITY`（Developer ID）构建后公证，并长期保持签名身份、Bundle ID 与安装位置；更新器会要求新包满足当前正式签名的 designated requirement。项目不会通过弱化签名要求或修改 TCC 数据库绕过权限。

开发者：构建两个工具后运行 `bash packaging/package-tools.sh` 生成 DMG 和更新 ZIP；发布前更新 `native-updates.json` 的版本、URL、SHA-256（以实际 ZIP 为准），上传所有资产后再公布清单。`python3 tests/native/run.py` 验证版本比较、来源、压缩包路径与链接拒绝，以及真实原生应用替换和启动失败回滚。
