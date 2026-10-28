# 0.1.0 验证报告

<!-- project-presentation-license-20261028:start -->
## 2026-10-28 项目介绍、Star 邀请与许可更新

机主要求产品介绍围绕回声译自身，不将 Bob 调研作为宣传内容；README 已移除调研导航，仅文末保留一行低调致谢。项目说明入口同步收敛，README 与官网末尾均加入自然的 Star 邀请。仓库简介和官网地址已更新。[项目首页](https://github.com/Blueeeecho/EchoLingo) · [官网](https://blueeeecho.github.io/EchoLingo/)。

机主核对范围后明确选择标准 MIT + Commons Clause v1.0，而非禁止所有商业用途。已保留完整官方条件与原 MIT 全文，新增 [授权说明](../LICENSING.md)，说明定义中的 Sell、源码可见、旧版本原授权及第三方许可。Cargo/npm 元数据和未来分发的许可文件配置同步；未来离线引擎源码包包含授权说明，第三方许可原件未修改。

公开介绍/许可补丁 main bae7220c56074c2af5097c54a266f1164668cad4 仅8个必要文件，未带入其他生产改动；官网 d1aa59ad37b30f3d68e1e0bc023dd64626564a04 已 built，仅3个静态文件变化。8份公开项目文件与6份官网文件逐字节核验通过；GitHub许可识别为Other/NOASSERTION，未误标纯MIT。官方条件逐段核对、Cargo metadata、JSON依赖不变检查、脚本语法与差异检查通过。Beta1的3项资产、tag和MIT原文均保持原样。[精确记录](validation/project-presentation-license-20261028.json)。
<!-- project-presentation-license-20261028:end -->


更新时间：2026-10-25。此报告分别记录本地测试、CI 和真实桌面边界；未完成项不视为通过。

| 验证项 | 结果 | 证据或限制 |
|---|---|---|
| TypeScript 类型、前端模型、生产构建 | 通过；45 项前端测试 | 增加自动换行、段落、代码、连字符与中英混排；npm run check、npm test、npm run build |
| 前端交互 / IPC 回归 | 通过 | 极简弹窗/菜单、源框自动高度、原文恢复、捕获先整理再请求/显示、手输不改、编辑期间捕获/Alt+A 排队；保留原有密钥与无焦点回归 |
| npm 依赖安全审计 | 通过 | 最近审计 0 vulnerabilities |
| Rust 编译与单测 | 本机通过，34 项 | 新增空取词/权限错误不弹 toast、剪贴板恢复失败保留、权限 kind 白名单与静态原生入口；保留真实 HTTP、签名、脱敏与凭据隔离用例 |
| macOS 原生 Vision OCR | 通过 | 实际生产静态入口识别生成图 2468、PNG Base64、段间距/换列/缩放/结构保序 fixture、Unicode/NUL 桥接；权限状态 PID 与宿主 Rust 进程一致 |
| Windows 原生 OCR | 通过 | run 40102326336 实际 Windows.Media.Ocr 识别生成图，并通过段落几何、缩放、保序夹具；非模拟识别结果 |
| Windows 取词与剪贴板桌面冒烟 | 通过 | run 40102326336：真实 Unicode 复制/读取、选区、空选区、Ctrl+C 回退、HTML/RTF/Unicode 剪贴板恢复、密码框拒绝 |
| Windows NSIS / macOS DMG | 通过 | 极简版 commit e15deaa/run 40102326336，三个任务全部成功；本地 Apple Silicon App 签名验证、极简版 DMG 校验通过 |
| 真实供应商 API | 未运行 | 使用虚构凭证与本地 HTTP 协议测试；未读取或验证其他应用的供应商凭证 |
| 用户电脑上的独立窗口 | 用户确认极简弹窗已生效 | 已启动更新后的独立 App，用户按 Alt+D 确认“已是简洁小弹窗”；原生自动化截图返回白色，不据此判定应用实际白屏 |
| 用户电脑的选文权限、交互截图与取消 | 尚待手动验收 | macOS 辅助功能/屏幕录制流程、Windows 实际目标应用 |
| Windows 多显示器 / 混合 DPI / 安装卸载 | 未完成 | CI 单屏专用测试窗口不能替代真实使用场景 |
| 代码签名 / Apple 公证 / 商店 | 未配置 | 安装包仅用于预览验证 |

## CI 记录

- [run 40093670591](https://github.com/Blueeeecho/EchoLingo/actions/runs/40093670591)：早期 Windows NSIS、macOS DMG 成功。
- [run 40097272065](https://github.com/Blueeeecho/EchoLingo/actions/runs/40097272065)：包含非激活浮窗、云 OCR 通用接口的三个任务全部成功；Windows 桌面冒烟通过。
- [run 40097996277](https://github.com/Blueeeecho/EchoLingo/actions/runs/40097996277)：供应商预设、百度/腾讯原生适配及凭据 origin 绑定的最终提交，Windows/macOS 与前端三个任务全部通过。
- [run 40102326336](https://github.com/Blueeeecho/EchoLingo/actions/runs/40102326336)：极简弹窗、自动换行与 OCR 段落几何，Windows/macOS 原生检查、安装包构建和前端交互全部通过。前一次 CI 暴露测试 HTTP socket 继承非阻塞模式的问题，已在测试夹具中显式恢复阻塞读取并重新验证。

桌面冒烟仅操作临时测试窗口，保存并恢复 CI 桌面的剪贴板，不读取用户应用内容；不覆盖全局快捷键注册、框选操作、多屏或 UAC 桌面。

## 发布状态

公开 GitHub 仓库已创建，对应提交的安装包已通过自动验证，并保存到本机输出目录供预览验收。稳定版仍需完成 Windows 手动测试计划、真实供应商账户与 Bob 行为研究验收项。源码 ZIP 不作为桌面安装包。
