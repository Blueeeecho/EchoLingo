# 0.1.0 验证报告

更新时间：2026-10-24。此报告分别记录本地测试、CI 和真实桌面边界；未完成项不视为通过。

| 验证项 | 结果 | 证据或限制 |
|---|---|---|
| TypeScript 类型、前端模型、生产构建 | 通过；45 项前端测试 | 增加自动换行、段落、代码、连字符与中英混排；npm run check、npm test、npm run build |
| 前端交互 / IPC 回归 | 通过 | 极简弹窗/菜单、源框自动高度、原文恢复、捕获先整理再请求/显示、手输不改、编辑期间捕获/Alt+A 排队；保留原有密钥与无焦点回归 |
| npm 依赖安全审计 | 通过 | 最近审计 0 vulnerabilities |
| Rust 编译与单测 | 通过，30 项 | 增加弹窗/管理尺寸和负坐标工作区钳制；保留真实 HTTP、签名、脱敏与凭据隔离用例 |
| macOS 原生 Vision OCR | 通过 | 实际识别生成图 2468、PNG Base64 往返；新增段间距/换列/缩放/结构文字保序几何 fixture |
| Windows 原生 OCR | 通过 | CI 实际 Windows.Media.Ocr 识别生成图；非模拟结果 |
| Windows 取词与剪贴板桌面冒烟 | 通过 | run 40097272065：真实 Unicode 复制/读取、选区、空选区、Ctrl+C 回退、HTML/RTF/Unicode 剪贴板恢复、密码框拒绝 |
| Windows NSIS / macOS DMG | 上版通过；极简版待 CI | commit 3c8d0f8/run 40097996277 已通过；极简版与 Windows OCR 几何需要新提交证据 |
| 真实供应商 API | 未运行 | 使用虚构凭证与本地 HTTP 协议测试；未读取或验证其他应用的供应商凭证 |
| 用户电脑上的独立窗口 | 用户确认可见 | 原生自动化截图返回白色；不据此判定应用实际白屏 |
| 用户电脑的选文权限、交互截图与取消 | 尚待手动验收 | macOS 辅助功能/屏幕录制流程、Windows 实际目标应用 |
| Windows 多显示器 / 混合 DPI / 安装卸载 | 未完成 | CI 单屏专用测试窗口不能替代真实使用场景 |
| 代码签名 / Apple 公证 / 商店 | 未配置 | 安装包仅用于预览验证 |

## CI 记录

- [run 40093670591](https://github.com/Blueeeecho/EchoLingo/actions/runs/40093670591)：早期 Windows NSIS、macOS DMG 成功。
- [run 40097272065](https://github.com/Blueeeecho/EchoLingo/actions/runs/40097272065)：包含非激活浮窗、云 OCR 通用接口的三个任务全部成功；Windows 桌面冒烟通过。
- [run 40097996277](https://github.com/Blueeeecho/EchoLingo/actions/runs/40097996277)：供应商预设、百度/腾讯原生适配及凭据 origin 绑定的最终提交，Windows/macOS 与前端三个任务全部通过。

桌面冒烟仅操作临时测试窗口，保存并恢复 CI 桌面的剪贴板，不读取用户应用内容；不覆盖全局快捷键注册、框选操作、多屏或 UAC 桌面。

## 发布状态

公开 GitHub 仓库已创建，对应提交的安装包已通过自动验证，并保存到本机输出目录供预览验收。稳定版仍需完成 Windows 手动测试计划、真实供应商账户与 Bob 行为研究验收项。源码 ZIP 不作为桌面安装包。
