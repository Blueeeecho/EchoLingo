# 0.1.0 验证报告

更新时间：2026-10-24。此报告分别记录本地测试、CI 和真实桌面边界；未完成项不视为通过。

| 验证项 | 结果 | 证据或限制 |
|---|---|---|
| TypeScript 类型、前端模型、生产构建 | 通过；20 项前端测试 | npm run check、npm test、npm run build |
| 前端交互 / IPC 回归 | 通过 | Chromium 隔离桩；覆盖空选区不聚焦、保存中锁定、失败恢复、默认无计时器、双密钥/部分凭据拒绝、跨供应商保存、Settings 无秘密字段 |
| npm 依赖安全审计 | 通过 | 最近审计 0 vulnerabilities |
| Rust 编译与单测 | 通过，28 项 | 真实本地 HTTP fixture、百度表单/token、腾讯公开已知 TC3 向量、多行响应、错误脱敏、响应上限、拒绝重定向、跨供应商凭据隔离 |
| macOS 原生 Vision OCR | 通过 | Swift helper 生成图像并实际识别 EchoLingo translation 2468；PNG Base64 往返 |
| Windows 原生 OCR | 通过 | CI 实际 Windows.Media.Ocr 识别生成图；非模拟结果 |
| Windows 取词与剪贴板桌面冒烟 | 通过 | run 40097272065：真实 Unicode 复制/读取、选区、空选区、Ctrl+C 回退、HTML/RTF/Unicode 剪贴板恢复、密码框拒绝 |
| Windows NSIS / macOS DMG | 通过 | 新供应商配置 commit 3c8d0f8 的 run 40097996277，两平台均成功构建实际安装包 |
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
