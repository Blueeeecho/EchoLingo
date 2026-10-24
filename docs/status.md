# 当前状态

更新日期：2026-10-24（Asia/Shanghai）。

阶段：0.1.0 预览版实现与验证中，尚未宣称稳定上线。

## 已完成
- 用户确认名称 EchoLingo · 回声译、Windows/macOS 工具链。
- 创建独立本地 Git 仓库与公开 GitHub 仓库。
- Bob 官方资料详细研究报告（31 条一手来源）。
- Tauri/Rust/TypeScript 架构与初版后端、平台 helper、界面实现。
- macOS Vision 使用生成图片的真实离线 OCR 自测通过（子任务验证，最终报告待汇总）。
- npm 依赖审计已修复最初测试工具依赖漏洞，当前安装结果为 0 vulnerabilities。

## 正在进行
- 本机 Rust stable 工具链安装，镜像下载使用官方 checksum 校验。
- 前端构建、自动化测试、Rust 编译与独立代码审查。
- GitHub Actions 在原生 Windows/macOS 上运行测试并生成安装包。
- 密钥与数据保存、快捷键冲突、焦点和窗口生命周期修复。

## 发布前仍需确认
- Windows helper 自测、NSIS 安装包构建结果。
- 真实 Windows 桌面的选文、截图、不同 DPI/多屏、Esc 取消、剪贴板恢复、卸载验收。
- macOS 权限授予与真实快捷键交互、DMG 构建。
- 真实第三方 API 端到端连接：需用户在应用中填写自己的 API 密钥，不读取其他应用的密钥。
- 代码签名、公证和商店发布尚未配置；首版应标为预览版。
