# EchoLingo · 回声译

一个独立维护的桌面软件项目。Windows 优先，兼顾 macOS。

GitHub: https://github.com/Blueeeecho/EchoLingo

## 已确认的产品要求
1. 名称含 Echo，用户已选 EchoLingo，中文名“回声译”。
2. 轻量，尽量贴近 Bob 的快捷键工作流。
3. 在其他应用选中文字，通过全局快捷键翻译。
4. 区域截图后本机 OCR，支持直接翻译或静默复制识别文字。
5. 支持用户自己的翻译 API、端点、模型与提示词。
6. 充分测试后发布，后续持续添加个人功能。
7. 默认静默托盘启动，按需出现；译文保留到用户点击窗口外立即隐藏，默认不使用倒计时（用户明确选择）。
8. 用本地文件夹、Git 和文档管理，不能只依赖聊天。
9. 使用多智能体并行开发；只需 Windows/macOS 桌面套件，不需要鸿蒙套件。

## 项目入口
- [Bob 详细调研](docs/bob-research.zh-CN.md)
- [实现计划](docs/implementation-plan.md)
- [当前进度和交接](docs/status.md)
- [个性化需求清单](docs/roadmap.zh-CN.md)
- [原生测试说明](docs/native-testing.md)
- [GitHub 构建](https://github.com/Blueeeecho/EchoLingo/actions)

## 维护方式
用户已在 Codex 项目栏创建 EchoLingo，本地项目路径已核验与当前仓库完全一致。后续可在该项目中建立聊天继续开发。当前旧聊天的归属仍由客户端界面管理。

本目录就是主工作副本，不要另建一个同名但互不同步的代码副本。
