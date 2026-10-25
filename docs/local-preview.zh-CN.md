# macOS 本机预览安装与性能验证

统一使用 `~/Applications/EchoLingo.app` 作为本机日常预览入口。源码中的 `target/debug`、`target/release` 和旁边的 `EchoLingo-installers` 是开发/分发产物，继续保留；它们不是必须同时启动的多个软件。脚本不会删除这些副本或改动凭据、设置、历史、剪贴板。

需要 macOS、自带的 `codesign`、`ditto`、`ps` 和 Python 3。无需额外 Python 包。在仓库根目录执行：

```sh
python3 scripts/macos-preview.py --help
python3 scripts/macos-preview.py inventory
python3 scripts/macos-preview.py install --dry-run
python3 scripts/macos-preview.py install
python3 scripts/macos-preview.py benchmark --launch
```

`install` 默认从 `src-tauri/target/release/bundle/macos/EchoLingo.app` 复制。尚未构建时先运行 `npm run tauri build -- --bundles app,dmg`，或用 `--source /绝对路径/EchoLingo.app` 指定已有安装包中的应用。只指定 `--bundles dmg` 时，Tauri 会在完成磁盘映像后清理中间 `.app`；此时可再用 `--bundles app` 生成本机安装来源。

`inventory` 只读检查 `/Applications`、`~/Applications`、仓库上级目录和本仓库 debug/release 的 bundle 目录。输出每个已找到副本的路径、版本、签名、可执行文件摘要及正在运行的实例。可用 `--search-root /其他目录` 添加范围，`--max-depth` 限制递归；它不是全磁盘搜索，也不删除 Launchpad 或 Spotlight 条目。

安装前必须匹配 bundle ID 与签名 ID `io.github.blueeeecho.echolingo`，并通过 `codesign --verify --deep --strict`。脚本先复制到目标目录旁的临时目录并再次验证，然后仅向当前用户拥有、路径/身份已验证的 EchoLingo 实例发送 SIGTERM，最多等待 5 秒。无法核验的同名进程或拒绝退出的实例会使安装中止，不强制杀进程。

旧的目标应用以 `.EchoLingo.backup-时间-随机值.app` 保留在同一目录，安装完成后输出实际路径。应用切换使用同一文件系统内的重命名；每次重命名是原子的，但两个重命名合起来不是一个原子事务。后续校验失败会自动恢复旧应用；断电或终止安装器时，查看目标旁 `.EchoLingo.preview-install.lock/transaction.json` 中记录的阶段、备份与临时目录，核对相应路径是否存在后手动恢复。该安装锁也会阻止后续安装覆盖恢复现场；确认无安装器运行并完成恢复后，再移除锁目录。失败恢复也失败时，脚本保留临时目录、备份及恢复记录，并明确报出位置。不会覆盖不同 bundle ID 的现有应用、符号链接目标或嵌套的源目录。

`--dry-run` 只检查并输出方案，不创建目录、复制应用、停止进程或启动程序。安装默认不启动；`install --launch` 明确请求安装后静默启动。脚本通过 `/usr/bin/open -g -j` 和已验证的 bundle 路径，使用 Launch Services 请求后台、隐藏启动。第二次启动可能触发单实例插件显示旧窗口，因此脚本在发现任何现存 EchoLingo 实例时拒绝再次启动。正常首次启动遵循应用自身的静默托盘设计，不发送显示窗口或聚焦请求。

源/目标目录的上级路径可以包含符号链接（例如迁移到其他磁盘的 `~/Applications`）；脚本先解析成真实路径，再进行安装、签名检查和进程匹配，输出也使用真实路径。应用 bundle 本身和可执行文件仍不允许是符号链接。

固定路径有助于避免使用错版本。当前预览是 ad hoc 签名；重建后的代码身份仍可能改变，不能承诺辅助功能/屏幕录制授权永久保留。签名完整性校验也不等同于 Developer ID、Gatekeeper 分发认可或 Apple 公证。[Apple 签名校验说明](https://developer.apple.com/library/archive/technotes/tn2206/)、[ad hoc 指定要求说明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。

TCC 的权限归因还依赖系统对 responsible code 的判断，进程 PID 与 bundle 路径正确仍不能证明某次权限归因。终端直接执行 `Contents/MacOS/echolingo` 属于开发启动方式，其进程树可能影响归因；脚本采用正常应用 bundle 启动流程，并且不会申请、重置或读取 TCC 授权。辅助功能/屏幕录制仍需通过已安装应用的设置进行真实验收。具体归因及跨次启动的授权保留结果应单独记录。[Apple 对 responsible code 与系统启发式的说明](https://developer.apple.com/forums/thread/678819)。

性能采样默认复用 `--app` 指定路径唯一的已运行实例；`benchmark --launch` 仅在没有任何 EchoLingo 进程时启动，并在采样后保持运行。默认先静置 3 秒，再采样 5 次、每次间隔 1 秒。采样时保持浮窗隐藏，不使用快捷键。参数示例：

```sh
python3 scripts/macos-preview.py benchmark --dry-run
python3 scripts/macos-preview.py benchmark --samples 10 --interval 1 --settle 5
python3 -m unittest discover -s scripts -p 'test_macos_preview.py' -v
```

输出为 JSON，包含 bundle/可执行文件字节数、主进程 RSS、区间 CPU 使用率与摘要。CPU 通过 `ps` 累计 CPU 时间差除以实际间隔计算，100% 表示使用一个核心；CPU 时间显示粒度为 0.01 秒。RSS/CPU 只包含 EchoLingo 主进程，**不包含独立的 WebKit/系统服务**，不能当成整个 WebView 进程组的总内存。

启动指标 `launch_to_process_observation_ms` 只表示“请求后台启动 bundle，到系统可见相同可执行文件路径且 RSS 非零”，包含 Launch Services 请求开销。它不表示托盘已就绪、WebView 完成加载、第一帧渲染、OCR 或网络翻译延迟。脚本通过 Apple `proc_pidpath` 查询可执行文件路径，避免收集命令行参数；仅采集当前用户的 EchoLingo 进程元数据。[Apple libproc 接口声明](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.h)。

夹具测试使用临时虚构 bundle 和文件摘要，覆盖预复制损坏、复制后验证失败、安装后回滚、退出失败、错误 bundle ID、符号链接与嵌套路径拒绝、安装锁和只读搜索；不伪装为真实 macOS 代码签名或桌面交互验收。真实应用还需单独完成授权、取词、截图框选/取消、输入法，以及 Windows 多屏与混合 DPI 验收。
