# 0.1.0 验证报告（进行中）

更新时间：2026-10-24。未完成项不能视作通过。

| 验证项 | 结果 | 证据或限制 |
|---|---|---|
| TypeScript 类型检查 | 通过 | npm run check |
| 前端生产构建 | 通过 | npm run build，JS 23.90 kB、CSS 24.15 kB；最终尺寸随修复更新 |
| 前端模型单测 | 通过 | Vitest，9 tests |
| npm 依赖安全审计 | 通过 | 升级测试依赖后 0 vulnerabilities |
| macOS 原生 Vision OCR | 通过 | Swift helper 生成图像并实际识别 EchoLingo translation 2468 |
| Rust 编译/单测 | 进行中 | 含真实本地 HTTP fixture、协议和配置验证 |
| Windows 原生 OCR | 待 CI | Windows.Media.Ocr 图像 fixture |
| Windows NSIS / macOS DMG | 待 CI | 两个平台原生构建 |
| 界面浏览器检查 | 进行中 | 仅界面，不冒充桌面快捷键验证 |
| 真实供应商 API | 未运行 | 不读取其他应用密钥，需用户在本应用配置 |
| 交互选文/截图/取消/剪贴板恢复 | 未完成 | 需有权限的真实桌面验收 |
| Windows 多显示器 / 混合 DPI | 未运行 | CI 不能替代实机交互 |
| 代码签名 / Apple 公证 / 商店 | 未配置 | 只允许预览版标识 |

## 发布状态
GitHub 仓库已创建。安装包完成测试后才发布预览附件；没有附件时请等待，不使用源码 ZIP 替代安装包。稳定版仍需要完成 Bob 研究报告中的逐项验收。
