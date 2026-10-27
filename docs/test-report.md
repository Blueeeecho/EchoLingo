# 0.1.0 预览版验证报告

更新时间：2026-10-25，Asia/Shanghai。本报告分别记录本机执行、CI 和真实桌面边界，未运行不算通过。[本轮原始本机证据](validation/macos-preview-20261025.json)。

## 2026-10-27 Windows 悬停窗口蓝框（真实回归待执行）

Windows Alt+S待机保留当前屏幕蓝边，并以DWM实际窗口边界提示鼠标悬停的应用。开始左拖清除悬停提示，继续任意区域OCR→原文填入→自动翻译，不吸附、不单击整窗截图。使用每屏额外4个薄边HWND，80ms元数据查询在UI线程，不进入同步hook；未知、桌面/任务栏、自身/排除或遮挡不一致仅保留屏幕框。

最终helper4a3674ff…已通过C#5/net48交叉编译、PS7AST及76项生产纯策略实际.NET8执行（含30hover）。审阅发现WindowFromPoint忽略disabled窗而可能误框下层，已用不跳过disabled的desktop-child hit保守核对修正。真实A/B/disabled遮挡/shell提示切换、自由ROI、无边框像素及完整app/NSIS回归仍待WindowsCI，不以host结果代替。Mac对应功能未实现；canonical7eafe813与已停止的本机Win10VM未操作。

## 本轮完成

| 验证项 | 结果 | 覆盖与限制 |
|---|---|---|
| 干净依赖安装、类型、生产构建 | 通过 | npm ci、npm run check、npm run build；实际 Tauri 优化构建与应用签名校验通过 |
| 前端单元测试 | 45 项通过 | 模型、凭据域、预设、捕获换行与原样输入 |
| 前端 UI/IPC 回归 | 通过 | 保存重入、空选区、IME/Enter/重复键、编辑/清空/停止/Esc/关闭/原生隐藏取消、编号分配前隐藏、陈旧事件/延迟布局、重开输入、隐私与错误保留；使用假 IPC，不是安装版桌面验收 |
| Rust | macOS 本机 50 项通过 | 真实本地 HTTP 断连、取消排序屏障、当前隐私设置、简繁目标/拒绝不回退、原子文件失败保留、历史计数/字节/超大单条、凭据隔离、签名、静态原生 OCR/ABI |
| 安装与回滚工具 | 22 项通过 | 临时虚构 bundle；签名/复制失败、改名失败、回滚及失败恢复、路径别名、同名进程拒绝、禁止重复启动；不伪装为真实签名测试 |
| 依赖安全审计/格式/diff | 通过 | npm audit 0 vulnerabilities；cargo fmt --check、git diff --check |
| macOS 原生 CLI | 通过 | 真实 Vision 识别 EchoLingo translation 2468，私有多项剪贴板恢复、PNG 8 MiB 边界、段落/代码/异常几何；不改用户通用剪贴板、不请求权限 |
| macOS 静态入口 | 通过 | 实际生产桥接、Unicode/NUL、进程身份与权限白名单；后台 Rust 线程明确跳过 AppKit 私有剪贴板夹具，该项由 CLI 主线程另验 |
| 最新 Windows 原生与 Rust CI | 通过 | 49 项 Rust，含真实独占文件锁替换失败及重试；真实系统 OCR 与 WinForms 选文/空选区/复制回退/富文本恢复/密码框拒绝；clipboardRestored=true，不含交互截图和多屏 |
| 最新双平台 CI 安装包 | 通过 | run 40172215129，Windows NSIS 与 macOS DMG 均生成；前端交互/Python 夹具任务也通过 |
| 本机打包 | 通过 | 优化 Apple Silicon .app 与 DMG；ad hoc 签名完整性通过，DMG hdiutil 校验有效 |
| 固定路径真实安装 | 通过 | ~/Applications/EchoLingo.app，签名/可执行文件摘要校验，Launch Services 后台启动；未删除开发与旧回退副本 |
| 默认静默启动 | 通过，元数据范围 | 启动并静置采样后，普通屏上窗口数为 0，前台应用不是 EchoLingo；不等于浮窗渲染或全部桌面交互通过 |
| 安装版交互自动化 | 未完成 | CUA 选择完整应用路径超时；bundle ID 因开发副本重复而有歧义。没有据此判定应用白屏，也不将浏览器回归替代安装版验收 |

## 本机性能记录

环境与原始八次采样见 JSON 证据。macOS Apple Silicon；应用保持默认隐藏。只采主进程，不含单独的 WebKit/系统进程。

- 优化可执行文件：4,906,848 字节；完整 app：5,011,832 字节。
- 空闲主进程 RSS：中位 97,536 KiB（约 95.25 MiB），最高 97,584 KiB；8 次约 1 秒间隔采样，区间单核 CPU 平均 0.123%。
- 启动请求到系统观测到对应进程：114.89 ms；不是托盘就绪、WebView 第一帧或真正冷启动时间。
- 构建结束后的 5 次生成图 Vision 识别：120.749 / 96.287 / 95.984 / 92.893 / 98.588 ms，中位 96.287 ms。范围仅为 1100×160 生成图的 Vision 调用，不含画图、框选、启动或网络。
- 并行构建/原生测试期间第一批采样曾出现 24,548.988 ms，随后 4 次约 92–112 ms；原始异常保留。原因未确认，不宣称冷启动 OCR 已达标，也不只挑选较快结果作为完整性能结论。

## CI 证据

- [run 40172215129](https://github.com/Blueeeecho/EchoLingo/actions/runs/40172215129)：本轮 3ec4f81，Windows/macOS/前端三任务全部通过；Windows 49 项 Rust（含真实文件锁用例），Mac 50 项 Rust，两个平台安装包均产出。[草稿 PR #1](https://github.com/Blueeeecho/EchoLingo/pull/1)。远端源码树 026e2c8de64697d7a3a9e9f7c7300de83df83564 与本机已测试树完全一致。
- [run 40167604502](https://github.com/Blueeeecho/EchoLingo/actions/runs/40167604502)：main 的 856e1a7，空弹窗、Enter 与静态原生权限修复的 Windows/macOS/前端三项通过。此记录早于本轮补强，不能替代当前分支 CI。
- [run 40102326336](https://github.com/Blueeeecho/EchoLingo/actions/runs/40102326336)：e15deaa，极简弹窗、换行整理、Windows 原生 OCR/选文/剪贴板受控冒烟与双平台安装包通过。
- 本轮 codex/preview-hardening 的 macOS CLI 私有剪贴板与 Python 安装回滚夹具也已实际执行通过。Mac CI 的生成图识别计时约 1,047.9 ms，再次说明本机热运行中位值不能代表所有环境或冷启动。

Windows 受控冒烟操作临时 WinForms 测试窗及该测试桌面的剪贴板，不读取用户应用。真实独占文件锁替换失败/重试用例已由本轮 Windows CI 执行通过；本机 macOS 不执行该条件编译项。

## 尚未通过的发布门槛

| 项目 | 状态 |
|---|---|
| 真实供应商账户 | 未运行；仅虚构凭据与本地 HTTP，未检查 Bob 密钥 |
| 最新安装版真实 IME、选文、截图框选/取消 | 尚待用户桌面验收；旧版简洁弹窗的用户确认不能套用于本轮 |
| macOS 同版重启与跨构建 TCC | 尚待验收；固定路径与进程内原生代码不能替代 Developer ID 身份 |
| Windows 真实目标应用/全局快捷键/多屏混合 DPI/安装升级卸载 | 尚待完整实机计划；CI 构建和专用测试窗不覆盖全部 |
| 全进程组内存/端到端冷启动与交互截图延迟 | 尚待实测；上方主进程和生成图结果仅覆盖所述范围 |
| 商业签名、Apple 公证、商店和自动更新 | 未配置；仅预览验证，不发布稳定版 |

当前公开源码与构建产物不代表已完成全部端到端验收。预览发布必须保留上述限制；源码 ZIP 不是安装包。

## 分发与草稿

Mac DMG、Windows x64 NSIS 和 SHA256SUMS-hardening.txt 已保存在本机旁边的 EchoLingo-installers，并上传至 [v0.1.0-preview.1 预览草稿](https://github.com/Blueeeecho/EchoLingo/releases/tag/untagged-c8da17a22fa76e07d45f)。发行仍是 draft=true / prerelease=true，未公开发布，未创建稳定版。

Windows ZIP 的 SHA-256 与 GitHub artifact digest 4fe5e663fe9e618f1c5582612412c2afe92c5afc0e6bfd71ef6a3c7b0b96f28c 一致。安装器 MZ/PE 头有效；其 SHA-256 为 830cae877360b96fe3f43487250123a53fc71d049dd691167bdbe8d7f86669ee。Mac DMG SHA-256 为 05bc7e7c6a21c01b4d0f34bb04cd540a0ee17ab819195902e6aa5b03e0a45e37。发行附件服务返回的 digest 与本地值一致。文件头和摘要核对不等于真实 Windows 安装验收。
