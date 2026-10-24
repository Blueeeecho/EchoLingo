# Bob 产品行为研究与 EchoLingo 复现规格

调研日期：2026-10-24（Asia/Shanghai）。目标产品：**EchoLingo · 回声译**。目标平台：先 Windows，再 macOS。

本报告基于实际打开的 Bob 官方文档、官方 GitHub、Mac App Store 和其他产品的官方仓库。**没有运行 Bob 做实机黑盒测试**；“已确认”表示官方明确描述，“推断/建议”表示为 EchoLingo 提出的设计与验收规格。不能将建议项作为 Bob 已实现的内部机制，也不能将本报告视作 EchoLingo 已经通过的测试报告。

## 1. 产品结论与竞争背景

Bob 的核心价值是把“取文本—翻译—阅读/复制结果”收敛为全局快捷键和临时浮窗。菜单栏常驻，选文、截屏、直接输入是不同入口，共享翻译服务。独立 OCR 是另一条链路，不应被实现成每次都顺带调用翻译 API。[官方介绍](https://bobtranslate.com/guide/)

“Windows 没有类似软件”这一前提需要修正：**Pot 已支持 Windows/macOS/Linux 的划词、OCR、多引擎、插件与系统离线 OCR**；CopyTranslator 也已有复制翻译产品和 Windows 分发。EchoLingo 的机会应定位为个人工作流、较低资源占用、稳定的快捷键与更清楚的隐私边界，而不是第一款 Windows 翻译工具。[Pot 官方仓库](https://github.com/pot-app/pot-desktop)、[CopyTranslator 官方仓库](https://github.com/CopyTranslator/CopyTranslator)、[CopyTranslator Windows 官方下载说明](https://copytranslator.github.io/download/windows.html)

Bob 官方仓库明确说明 Bob **不是开源软件**。EchoLingo 应按公开行为独立编写，使用自己的名称、图标、布局与实现；本次没有复制其代码、图标或大段文案。[Bob 官方仓库](https://github.com/ripperhe/Bob)

## 2. 当前版本、价格与文档冲突

| 项目 | 本次确认 | 对复现的含义 |
|---|---|---|
| 最新版本 | 1.21.2，2026-10-13 | 不以 2022 社区版或旧博客替代当前产品 |
| 平台 | Mac 专用；当前最低 macOS 12.0 | Windows 需要独立适配系统集成 |
| 安装体积 | 中国区 App Store 页面显示 20.4 MB | 这是商店展示值，不等同内存、安装后占用或 Windows 包体目标 |
| 界面语言 | 简体中文、繁体中文、英语 | EchoLingo 初版可先中文/英文 |
| 购买 | 免费下载、有内购；中国区 Bob Pro ¥58，另列 Free Trial ¥0 | 价格随商店地区/时间改变；不能解释为所有 API 免费 |
| Markdown | 1.21.0 引入；渲染需要 macOS 13，12 上显示纯文本 | 首版纯文本足够，富文本需单独安全处理 |

依据：[App Store 中国区](https://apps.apple.com/cn/app/id1630034110)、[官方更新历史](https://bobtranslate.com/general/changelog.html)、[Markdown 官方公告](https://bobtranslate.com/blog/2026-09-21-markdown-plugin.html)。

发现的资料冲突及取舍：

- 旧“介绍”页写最多同时 10 个翻译服务；详细翻译文档和商店描述写 12 个。规格采用 **12**，但 EchoLingo 不必在首版追平数量。
- 旧“介绍”页写静默 OCR 无默认快捷键；详细 OCR 文档和商店描述为 **Option+C**，采用后者。
- OCR 入门页提到 macOS 11 可离线 OCR；这描述的是功能能力，不代表当前 App 能装在 macOS 11。当前安装门槛以商店和版本记录的 12.0 为准。
- 静默翻译博客标题使用 1.18.0；2025-08-11 官方版本记录也确实有静默翻译。原图翻译从 1.19.0（2025-12-28）引入 Beta，1.20.0（2026-05-21）扩展 OCR 插件支持；不能把原图翻译写成所有历史版本的稳定功能。
- 官方 API 申请页中的模型、价格和申请要求可能滞后，且页面自己声明可能过时。本报告不把这些表格当作 API 厂商的实时价格承诺。

## 3. 输入入口与快捷键行为

### 3.1 翻译入口

下表是官方公开的行为摘要；Option 为 macOS 的 ⌥，不是 Windows 的组合键承诺。[翻译操作文档](https://bobtranslate.com/guide/quickstart/translate.html)

| 入口 | Bob 默认快捷键 | 用户步骤 | 结果与边界 |
|---|---|---|---|
| 划词翻译 | Option+D | 在其他 App 选中文本后触发 | 适合可选择且能复制的文本；显示临时翻译窗 |
| 截图翻译 | Option+S | 触发后框选屏幕区域 | OCR 先取文字，再调用翻译服务；应能修订识别文本 |
| 输入翻译 | Option+A | 打开输入窗，输入文本，Enter | 用于取词不准、手动修改或纯输入 |
| 静默划词翻译 | 无默认值 | 在可编辑区域选中内容后触发 | 不打开普通译文窗，完成后以译文替换原文 |
| 静默输入框翻译 | 无默认值 | 光标留在可编辑输入框后触发 | 获取整个输入框内容并替换 |
| 原图翻译 | 无默认值 | 截取区域 | 译文放回图像上的对应位置，不打开普通翻译窗 |
| PopClip | 外部扩展 | 选文后点扩展图标 | 依赖 PopClip，不能算零安装默认能力 |

### 3.2 “静默”必须分清三种任务

1. **静默截图 OCR：图像 → 文字 → 剪贴板。** 不产生译文、不应消耗翻译 API；不打开结果窗。
2. **截图翻译：图像 → 文字 → 译文 → 浮窗。** 用户说的“无感 OCR 翻译”通常是这一快捷链路：无需中间手动复制，而不是全程没有 UI。
3. **静默替换翻译：可编辑原文 → 译文 → 写回源输入框。** 它需要可靠保留焦点和选区，风险明显高于前两种。

Bob 静默翻译会展示一个可取消的状态条，字符数反映已输出字符；点击进度区域可以展开普通翻译窗。只调用已启用的第一个翻译服务，避免多引擎并发浪费。官方明确提示：翻译时改变选区或切换 App 可能导致写回异常或终止。[静默翻译官方公告](https://bobtranslate.com/blog/2025-08-11-silent-translate.html)

**EchoLingo 建议：首版优先前三个普通入口和静默 OCR。静默写回排到 P2；实现时必须在写回前校验原进程、窗口、焦点控件和选区，任一变化则取消写回，只允许用户主动复制。** 这项校验是 EchoLingo 的设计建议，未确认 Bob 内部如何实现。

### 3.3 Windows 初始键位建议

| 命令 | 建议初值 | 说明 |
|---|---|---|
| 选文翻译 | Ctrl+Alt+D | 保持字母联想；注册失败应提示冲突并允许改键 |
| 截图翻译 | Ctrl+Alt+S | 不覆盖系统 Win+Shift+S |
| 输入翻译 | Ctrl+Alt+A | 触发时才请求输入焦点 |
| 截图 OCR | Ctrl+Alt+O | 与翻译分开 |
| 静默截图 OCR | Ctrl+Alt+C | 完成只写剪贴板，轻量成功提示可关闭 |

上述为建议；某些键盘布局把 Ctrl+Alt 用作 AltGr，必须提供可修改键位和布局兼容测试。实际默认值以项目实现为准。

## 4. 浮窗、焦点与日常操作

### 4.1 已确认的用户可见行为

- 普通翻译结果悬浮于源应用之上，点击外部空白区域后消失；可以钉住。
- 翻译窗宽度可拖动，高度随内容变化，最大高度可以配置。
- 快捷设置、原文语言手动指定、字体大小调整、重试、收藏、复制等操作围绕当前结果进行。
- 可启用多家翻译服务；偶尔使用的服务可以钉到语言栏旁，按需点击才执行，下次查询再次收起。
- OCR 窗也采用外部点击消失和钉住模式，支持调整尺寸。

依据：[翻译详细文档](https://bobtranslate.com/guide/quickstart/translate.html)、[OCR 详细文档](https://bobtranslate.com/guide/quickstart/ocr.html)。

### 4.2 Bob 翻译窗局部快捷键

| 功能 | macOS |
|---|---|
| 翻译 / 输入内换行 | Enter / Shift+Enter 或 Command+Enter |
| 重试 | Command+R |
| 收藏 | Command+S |
| 关闭 | Command+W 或 Esc |
| 钉住 | Command+P |
| 字体放大/缩小 | Command++ / Command+- |

EchoLingo 可采用相同操作语义，Windows 按平台约定映射 Ctrl。快捷键只有在翻译窗获得交互焦点时才生效，不应拦截源软件的 Ctrl+S。

### 4.3 尚未被官方文档充分规定的部分

没有找到足以完整确认的 Bob 契约：浮窗是否永不激活、每种调用后的焦点归还策略、鼠标旁定位的精确偏移、跨屏时的锚点、混合 DPI 变换、跨显示器框选、HDR/受保护画面、系统睡眠后的快捷键恢复。文档中的“任何应用程序”不能当作这些场景全部受支持的证明。

**以下全部是 EchoLingo 的验收设计：**

- 选文时先获取来源文本，再显示结果，避免先抢焦点导致复制落在自己窗口。
- 输入模式主动聚焦；选文/截图模式先保留来源身份。用户点击译文窗后可编辑，不把键盘永久锁在工具窗。
- “固定窗口”明确决定点击外部不关闭；是否长期置顶应为独立设置，不混淆固定位置、跨桌面和 topmost。
- 默认在鼠标所在显示器的工作区内定位；窗口边界夹紧，避开任务栏；长结果内部滚动。
- 一张捕获图必须有明确的物理像素宽高、屏幕原点、显示器缩放。UI 逻辑坐标不得直接当 OCR 裁剪坐标。
- 100%、125%、150%、200% 混合缩放，主屏在右/上、负坐标副屏，显示器热插拔，都应进入人工验收矩阵。
- 框选 Esc、零面积、跨屏拖拽和切换应用有明确取消结果；取消不改剪贴板、不留遮罩、不发出翻译请求。

## 5. OCR 与原图翻译

### 5.1 独立 OCR

Bob 提供截图 OCR（Shift+Option+S）、静默截图 OCR（Option+C）、访达选图 OCR（无默认键，可多图）。独立 OCR 有连续识别拼接、二维码检测、自动复制、智能段落处理；二维码和自动复制在文档中标明默认开启。多列文档官方建议按单列框选。[OCR 文档](https://bobtranslate.com/guide/quickstart/ocr.html)

OCR 引擎与翻译引擎应拆开：改“图片读错字”应该切换/配置 OCR；改“译意不佳”应该调整翻译服务。Bob 同时有本地识别和云端识别；本地 OCR 能离线工作不意味着后续云端翻译离线。

### 5.2 原图翻译的结构要求

原图翻译不能只输出一个整段字符串。Bob 从 1.20.0 的 OCR 插件扩展可确认：识别结果可带文字坐标、区域/段落层次；只有声明能返回坐标的 OCR 插件才进入原图翻译可用列表。坐标归一到 [0,1]，图像左上为原点；同时传递图像像素宽高。旧插件仍可用于普通 OCR。[OCR 插件升级公告](https://bobtranslate.com/blog/2026-05-21-ocr-plugin-boundingbox.html)、[OCR 结果结构](https://bobtranslate.com/plugin/object/ocrresult.html)

**EchoLingo 原图翻译建议流水线：**

1. 截图时冻结区域与物理坐标；不修改底层 App。
2. OCR 返回按阅读顺序的行、置信度、四边形/矩形边界。
3. 由独立布局模块聚合段落，保留段落 ID；无法可靠判断的双栏不能合成一句。
4. 翻译以段落 ID 对齐，不按译文行数猜回原文坐标。
5. 独立 overlay 显示译文，允许临时查看原文和退出；字体自适应有最小字号，溢出进入卡片而不是截掉字。
6. OCR 或翻译局部失败保留对应原文，显示可重试提示，不清空整屏。

此项是 P2：背景覆盖、混合缩放、文字扩张和点击穿透都需要额外设计。把译文放到普通结果窗不应在发布说明里称作已支持原图翻译。

## 6. 翻译引擎、自定义 API 与插件

### 6.1 服务模型

Bob 将翻译功能拆为文本翻译、文本识别、语音合成；OCR 模块主要使用文本识别。内置免费服务、自带密钥服务、第三方插件是不同接入方式。服务商计费与 Bob 购买费用分离。[服务模型](https://bobtranslate.com/guide/advance/service.html)

当前官方目录包含传统翻译商、OpenAI/Azure/Claude/Gemini/DeepSeek/通义等 AI 服务，以及 Ollama、LM Studio 本地模型入口。名单会变化，不应为追求数量把不可用的端点塞入首版。官方已在 1.21.0 下线零一万物和金山词霸，说明服务可用性维护是持续成本。[服务目录](https://bobtranslate.com/service/)、[更新历史](https://bobtranslate.com/general/changelog.html)

### 6.2 自定义 Prompt

Bob 可配置 system 角色和 user 指令，模板中可引用输入文本和目标语言；也可重命名实例用于不同任务。模板漏掉文本变量时，结果可能完全偏离输入。[自定义 Prompt 文档](https://bobtranslate.com/faq/openai-custom-prompt.html)

**EchoLingo 首版建议：配置一个 OpenAI 兼容入口，而不是自带永久免费公共代理。** 配置至少有：实例名称、base URL、API key、模型名、源/目标语言、提示模板、超时、是否流式。提供本地连接测试；显示将发送到哪个域名。文本来自外部软件，必须被视为待翻译数据，避免把其中的提示词当应用命令执行。

模板变量和配置结构应为 EchoLingo 自己的公开契约。URL 组装需覆盖带/不带 /v1、末尾斜杠、自定义 path；明确区分 chat/completions 兼容协议与其他厂商原生协议，不能声称任意 API 都兼容。

### 6.3 Bob 插件机制与兼容边界

官方插件是 `.bobplugin` 压缩包，典型文件含 `info.json`、`main.js` 和资源。插件先安装，再作为服务实例启用。运行时是 JavaScriptCore，**不是浏览器，也不是 Node.js**。[使用插件](https://bobtranslate.com/guide/advance/plugin.html)、[开发插件](https://bobtranslate.com/plugin/)

`info.json` 声明标识、版本、类别、最低 Bob 版本与选项。文本翻译插件暴露支持语言与翻译方法，可回调进度/最终结果；OCR 和 TTS 各自有独立接口。网络、文件、定时器等通过 Bob 提供的 API 访问。[元信息](https://bobtranslate.com/plugin/quickstart/info.html)、[翻译插件](https://bobtranslate.com/plugin/quickstart/translate.html)、[OCR 插件](https://bobtranslate.com/plugin/quickstart/ocr.html)、[TTS 插件](https://bobtranslate.com/plugin/quickstart/tts.html)

1.21.0 翻译结果增加明确的纯文本/Markdown/按行格式；老的段落数组继续兼容，但拼接规则改变。[插件 Markdown 公告](https://bobtranslate.com/blog/2026-09-21-markdown-plugin.html)

**复现建议与非目标：**

- MVP 先做声明式服务配置，不加载任意 JS；这是“自定义 API”需求的最小交付。
- P1 增加多个实例、并发结果卡、按需引擎和错误隔离。
- P2 再考虑受限插件运行时、签名/来源信息、网络域名授权、超时、资源上限、卸载与升级。
- **没有实现完整 Bob API 兼容层之前，不得宣称能直接运行 `.bobplugin`。** 文件扩展名改名不能实现兼容。

### 6.4 错误与取消的最小契约（EchoLingo 建议）

每次请求有递增 request ID 与取消信号；新任务取消旧任务；迟到的结果不能覆盖新文本。区别展示未配置、401/403 密钥问题、429 限额、网络超时、无正文、截断、用户取消和本地 OCR 无文本。部分服务失败只影响该卡片。重试必须由用户明确触发或有次数上限，防止反复计费。API key、认证头和原文默认不进入诊断日志。

## 7. 词典、朗读、历史、收藏与迁移

### 7.1 查词与 TTS

Bob 主要面向段落翻译，服务返回词典结果时可以显示。当前官方确认内置简明英汉词典可离线使用；有道从 2024-04-23 起不再返回该词典信息，金山词霸从 1.21.0 下线。词典能力来自数据源，不是所有翻译 API 固有能力。[词典 FAQ](https://bobtranslate.com/faq/translate-show-dict.html)

语音朗读可作用于原文/译文；本地和云端语音合成独立于翻译服务。EchoLingo P1 可以先接系统 TTS，明确标识音色/语言可用性；查词数据必须有合法再分发许可，不能把 Bob 的离线词库打进自己的安装包。[官方介绍](https://bobtranslate.com/guide/)、[TTS 插件契约](https://bobtranslate.com/plugin/quickstart/tts.html)

### 7.2 历史与收藏

Bob 可保存历史、收藏结果、导出收藏。官方多设备文档进一步明确：设置可以导出/导入；**历史记录和收藏夹只能导出，不能导入**；没有自动跨设备同步。配置导入还可能带入 API key 和插件。[多设备与迁移 FAQ](https://bobtranslate.com/faq/multi-device-usage.html)

EchoLingo 可以改进为显式 JSON 导出和可选导入，但这是新增规格，不能说是 Bob 原样复现。建议：历史有容量上限、可关闭记录、可清空；收藏持久化；导出默认不包含密钥和截图。只有用户主动选择“包含凭据”才能产生含密钥备份，且必须清楚标示。首版如果仅支持 JSON 导出，应如实说明，不能泛称已实现完整迁移。

## 8. 权限、隐私与离线边界

Bob 官方披露按需申请辅助功能（取选文）、屏幕录制（截屏）、可选自动化（浏览器取选文）和剪贴板读写。云端服务会把文字/图片直接发往被启用的服务商；密钥保存在本地。官方政策不覆盖用户自己安装的第三方插件，且提到脱敏使用统计和崩溃数据。[隐私政策](https://bobtranslate.com/general/privacy.html)

授权异常并非稀有边角：官方有辅助功能和屏幕录制权限修复文档，截图可能黑/白/灰屏，授权后可能要重启 App。不能把“用户曾经点允许”当永久可用。[取词权限 FAQ](https://bobtranslate.com/faq/selection-error.html)、[截图权限 FAQ](https://bobtranslate.com/faq/screenshot-error.html)

BobHelper 是针对早期 macOS 15 Option+字母快捷键限制的补丁；官方写明 macOS 15.2 起已修复。不要把这个辅助 App 当作所有当前 Mac 必装组件。[BobHelper 官方说明](https://bobtranslate.com/guide/advance/bobhelper.html)

| 任务 | 网络边界 | EchoLingo 应如何描述 |
|---|---|---|
| 系统本地 OCR | 识别可本机完成 | 本地截图识字，不主动上传图像 |
| OCR 后云翻译 | OCR 本地，但文字会发出 | 不能叫“完全离线” |
| 云端 OCR | 选区图像发往 OCR 商 | 首次启用清楚说明图像目的地 |
| 云端翻译 | 原文发往翻译端点 | 展示端点，密钥保存方式透明 |
| 本地模型翻译 | 模型已下载、服务在本机、无云端回退时可离线 | 用户自己运行模型；模型下载与内存不计入轻量 UI 的宣传 |
| 本地词典/TTS | 取决于资源是否已安装 | 缺资源提示安装，不静默切到云端 |

Bob 的 Ollama 接入说明确认可本地模型翻译，同时提示模型消耗内存和性能资源。[Ollama 接入文档](https://bobtranslate.com/service/translate/ollama.html) EchoLingo 可以保持安装包轻量，但不能同时承诺“不下载模型、全离线、覆盖所有语言、接近旗舰云模型质量”。

Windows 的权限和高权限窗口行为不能从 macOS 说明机械套用。EchoLingo 应以普通权限运行，遇到受保护内容、登录安全桌面或无法复制的窗口时明确失败并提供截图/手动输入入口；不为实现全应用取词而默认要求管理员权限。

## 9. 可实现的操作状态机

以下为 **EchoLingo 设计规格**。它们抽象自公开产品行为，并非对 Bob 源码的描述。

### 9.1 共用任务生命周期

```text
Idle
  → Triggered(command, requestId, sourceWindow, pointerMonitor)
  → CapabilityCheck
  → AcquireText | SelectRegion | FocusInput
  → Recognize? → Normalize → DispatchProvider(s)
  → Stream/Result → Present | CopyOnly
  → Dismiss → Idle

任一阶段 → Cancelled → 清理遮罩/临时图/请求 → Idle
任一阶段 → Error(code, recoverable) → 可理解提示 → 重试或Idle
新任务触发 → 取消旧requestId；旧结果不得提交UI或剪贴板
```

### 9.2 选文翻译

```text
触发 → 记住源窗口与剪贴板版本
 → 尝试安全的选文获取
 → 必要时受控复制并等待剪贴板确有新文本
 → 成功：规范化、发翻译请求、展示结果
 → 没有新文本：明确“未取到选文”；不翻译旧剪贴板
 → 如果使用临时剪贴板：只有剪贴板仍归本任务所有时才恢复
```

剪贴板恢复不是无条件写回：用户在请求期间复制了其他内容时，恢复旧数据会丢失用户操作。纯文本恢复也不等同保留原剪贴板中的图像、富文本和文件列表；若首版有这种限制，需要文档明确。

### 9.3 截图翻译/截图 OCR/静默 OCR

```text
触发 → 检查捕获能力 → 冻结画面/显示框选
 → pointerDown → pointerMove → pointerUp
 → Esc/零面积：取消；不请求OCR、不改剪贴板
 → 有效区域：关闭框选并裁剪正确的物理像素
 → 本地OCR
 → 无文本：错误提示；保留现有剪贴板
 → mode=translate：送文字给翻译服务 → 翻译浮窗
 → mode=ocr：显示识别结果窗 → 可复制/修订
 → mode=silentOcr：仅在成功时写文字到剪贴板 → 轻提示 → Idle
```

### 9.4 窗口状态

```text
Hidden → Showing(loading/result) → Interacting
Interacting + outsideClick + !pinned → Hidden
Interacting + outsideClick + pinned  → 保持可见
任意可见态 + Esc/关闭 → Hidden
任意可见态 + 输入模式 → 聚焦输入框
源显示器移除 → 移到有效工作区，避免永久在屏外
```

关闭窗后是否继续网络请求必须有统一政策：建议非固定临时窗取消请求，历史结果不落盘半成品。静默 OCR 的关闭/取消与任务完成写剪贴板也要用 request ID 防止竞态。

## 10. 功能矩阵与发布分层

此表是 **目标路线图，不是当前完成清单**。MVP 表示首个可用预览应具备，P1 表示后续优先增强，P2 表示需要更多设计/原生测试。

| 能力 | Bob 依据 | EchoLingo 层级 | 达标条件 |
|---|---|---|---|
| 托盘常驻、退出 | 介绍页 | MVP | 关闭结果窗不退出，托盘可彻底结束 |
| 输入翻译 | 翻译页 | MVP | 回车翻译、可复制、可取消、错误清晰 |
| 全局选文快捷键 | 翻译页/权限FAQ | MVP | 常用编辑器和浏览器通过；不误译旧剪贴板 |
| 截图翻译 | 翻译页 | MVP | 框选→本地OCR→自定义引擎一条链路 |
| 静默截图 OCR | OCR页 | MVP | 不开结果窗、不调用翻译、成功才改剪贴板 |
| 截图 OCR 结果窗 | OCR页 | MVP | 识别文本可复制与修订 |
| 自定义翻译端点与模型 | Prompt/插件文档 | MVP | 用户自己的服务可用，无预置秘密密钥 |
| 快捷键配置/冲突提示 | Bob设置入口 | MVP | 重复/占用可诊断；配置可持久化 |
| 钉住、外点收起 | 翻译/OCR页 | MVP | 状态一致，Esc始终可退 |
| 单次任务取消/重试 | 插件及翻译文档 | MVP | 旧响应不覆盖新结果，不无限重试 |
| 有上限的历史/收藏/导出 | 翻译/迁移FAQ | MVP/P1 | 以实际实现标示；隐私设置清楚 |
| 混合DPI、多屏 | 未找到完整Bob契约 | MVP发布门槛 | 至少单屏和普通双屏通过；复杂边界如实列明 |
| 多服务结果比较 | 翻译页12服务 | P1 | 独立错误/取消，默认并发数受控 |
| 本地 TTS 与朗读按钮 | 介绍/TTS接口 | P1 | 明确语言和音色缺失时行为 |
| 离线词典 | 词典FAQ | P1 | 数据许可清晰、资源独立下载 |
| 连续OCR、多图OCR、二维码 | OCR页 | P1 | 次序稳定、追加去重有定义 |
| 术语表/学术翻译模板 | EchoLingo个性需求 | P1 | 用户可编辑，不伪称Bob已确认能力 |
| 自定义HTTP声明式模板 | EchoLingo扩展 | P1 | 协议、认证、返回路径明确 |
| 原图译文覆盖 | 1.19/1.20公告 | P2 | 坐标/段落对齐，易关闭，保留原文 |
| 静默选文/输入框替换 | 静默翻译公告 | P2 | 焦点变化必停止，支持撤销 |
| 任意脚本插件/Bob兼容 | 开发插件文档 | P2 | 单独安全与兼容审计，未实现不得宣传 |
| 跨设备同步/账号 | Bob没有自动同步 | P2或不做 | 用户明确需要后再引入服务器成本 |

## 11. 验收场景与测试证据要求

### 11.1 必测用户任务

| ID | 场景 | 预期 | 需要证据 |
|---|---|---|---|
| A01 | Notepad/VS Code 选择中英混排，按选文键 | 只翻译所选内容；原文不变 | Windows实机录屏/日志 |
| A02 | 浏览器普通文本/网页输入框/PDF选文 | 能取词，失败不读旧剪贴板 | 每种应用的手测记录 |
| A03 | 没有选文，剪贴板已有旧文字 | 提示未取到，不发送旧文字 | 可控端点请求计数 |
| A04 | 选文失败后手动输入 | 不必重启；输入模式可用 | UI自动化或人工 |
| A05 | 截取中英文图片后翻译 | OCR文本可见，译文来自配置端点 | 本地图像夹具+实机 |
| A06 | 静默OCR | 剪贴板为识别文字，无翻译请求，无结果窗 | 请求记录/窗口状态 |
| A07 | 框选按Esc/零面积/空白图 | 不调用翻译，不改剪贴板，不留遮罩 | 实机/集成测试 |
| A08 | 副屏125%与主屏200% | 裁剪区域与鼠标框一致 | Windows双屏实机 |
| A09 | 任务期间切换应用并复制新内容 | 不把旧剪贴板恢复覆盖新内容 | 剪贴板竞态测试 |
| A10 | 连续快速触发两次，首个响应慢 | 展示第二次结果，旧结果不能污染 | 延迟Mock端点 |
| A11 | API 401、429、超时、空响应、坏JSON | 分类提示，可重试，不泄露key | HTTP单元/集成 |
| A12 | 自定义base URL有斜杠或含/v1 | 正确组装URL，不重复路径 | URL单测+Mock |
| A13 | 非英文模型/自定义模型/本机服务 | 模型名原样传递，离线边界如实显示 | Mock+可选真实API |
| A14 | 外点关闭/固定/拖动/长文滚动 | 不意外消失，不永久抢焦点 | 原生实机 |
| A15 | 屏幕捕获权限未开/语言包缺失 | 给出原因和恢复入口，无无限弹窗 | 清洁用户配置 |
| A16 | 托盘退出再启动/快捷键冲突 | 清理旧注册，下次可正常注册 | 连续启动关闭 |
| A17 | 历史关闭、清空、收藏、导出 | 按设置落盘，导出不带密钥 | 文件断言+人工 |
| A18 | 断网运行OCR与本地模型 | 本地OCR可用；云翻译清楚失败 | 断网实测 |

### 11.2 性能预算（建议值，未实测）

- 不包含模型和 OCR 语言资源的初始安装包优先控制在 30 MB 级；必须同时说明系统 WebView/运行库是否外置，否则包体比较失真。
- Windows 普通开发机空闲状态优先以常驻内存低于 150 MB 为目标；应测进程树而非只测主进程。
- 快捷键到框选/结果窗可见目标 p95 < 200 ms；本地 OCR 1 MP 清晰截图目标 p95 < 1.5 s。机器、语言、DPI和引擎必须记录。
- 网络翻译时间独立计量连接/首字符/全文，不能把云模型耗时归入本地UI指标，也不能在首字符到达时宣称全部完成。
- 连续运行至少 30 次截图任务和 100 次选文任务，比较初末内存、线程和临时文件数；不把一次能打开窗当稳定性测试。

真正对外发布前，应记录 OS 版本、CPU/内存、显示器配置、构建 SHA、安装包摘要、测试结果和未通过项。当前环境无法执行的 Windows 原生路径应标为“待 Windows 实机验证”，不能用 macOS 编译成功代替。

## 12. 初版范围建议

EchoLingo 的可交付核心是：托盘 + 全局快捷键 + 可靠选文 + 系统本地OCR + 输入/截图翻译 + 静默OCR + 用户自己的API + 临时结果窗。先把这条日常链路稳定，再追求引擎数量和原图覆盖。历史、收藏、术语表和朗读是可增量添加的个人效率功能。

发布表述建议使用“Windows 优先的早期预览”。只有相应系统的原生场景被验证后才列为支持；未签名安装包、测试覆盖和API配置依赖需要清楚列示。发布源代码和预览包可以是初版上线，但不等于已达到 Bob 1.21.2 的功能与稳定性。

## 13. 一手来源登记

全部访问日期均为 **2026-10-24**。下表链接均已实际打开，不将搜索摘要单独作为结论依据。

| 来源 | URL | 用途/注意 |
|---|---|---|
| Bob App Store 中国区 | https://apps.apple.com/cn/app/id1630034110 | 当前版本、平台、体积、价格；地区价格会变化 |
| Bob 官方仓库 | https://github.com/ripperhe/Bob | 非开源声明、公开功能概述 |
| 官方介绍 | https://bobtranslate.com/guide/ | 菜单栏、浮窗、TTS；个别数量/默认键滞后 |
| 翻译指南 | https://bobtranslate.com/guide/quickstart/translate.html | 入口、窗口、12服务、快捷键 |
| OCR指南 | https://bobtranslate.com/guide/quickstart/ocr.html | OCR/静默OCR、多图、连续、分段 |
| 更新历史 | https://bobtranslate.com/general/changelog.html | 版本日期、系统要求、兼容性变更 |
| 服务模型 | https://bobtranslate.com/guide/advance/service.html | 翻译/OCR/TTS、费用分离 |
| 服务目录 | https://bobtranslate.com/service/ | 服务类型，厂商名单随时间变化 |
| 插件使用 | https://bobtranslate.com/guide/advance/plugin.html | 安装、启用、压缩包形式 |
| 插件开发入口 | https://bobtranslate.com/plugin/ | JavaScriptCore与宿主API边界 |
| 插件元信息 | https://bobtranslate.com/plugin/quickstart/info.html | 类别、最低版本、选项 |
| 文本翻译插件 | https://bobtranslate.com/plugin/quickstart/translate.html | 查询、进度、结果接口 |
| 文本识别插件 | https://bobtranslate.com/plugin/quickstart/ocr.html | 图像尺寸、坐标能力声明 |
| 语音合成插件 | https://bobtranslate.com/plugin/quickstart/tts.html | TTS独立服务与超时 |
| OCR结果对象 | https://bobtranslate.com/plugin/object/ocrresult.html | 行/段/区域结构与坐标 |
| 静默翻译公告 | https://bobtranslate.com/blog/2025-08-11-silent-translate.html | 原文替换、取消、焦点风险 |
| OCR插件公告 | https://bobtranslate.com/blog/2026-05-21-ocr-plugin-boundingbox.html | 1.20原图OCR适配 |
| Markdown公告 | https://bobtranslate.com/blog/2026-09-21-markdown-plugin.html | 1.21结果格式与旧插件兼容 |
| 自定义Prompt FAQ | https://bobtranslate.com/faq/openai-custom-prompt.html | 角色、用户指令、文本变量 |
| 词典FAQ | https://bobtranslate.com/faq/translate-show-dict.html | 当前离线词典与已下线服务 |
| 多设备FAQ | https://bobtranslate.com/faq/multi-device-usage.html | 购买、设置迁移、历史仅导出 |
| 隐私政策 | https://bobtranslate.com/general/privacy.html | 按需权限、服务商数据流、统计边界 |
| 取词故障FAQ | https://bobtranslate.com/faq/selection-error.html | 辅助功能授权故障 |
| 截图故障FAQ | https://bobtranslate.com/faq/screenshot-error.html | 屏幕录制授权与黑屏 |
| Apple翻译FAQ | https://bobtranslate.com/faq/use-apple-translate.html | 快捷指令依赖；不是Windows API |
| BobHelper | https://bobtranslate.com/guide/advance/bobhelper.html | 早期macOS15快捷键补丁，15.2后无需 |
| Ollama接入 | https://bobtranslate.com/service/translate/ollama.html | 本地翻译与模型资源边界 |
| OpenAI接入 | https://bobtranslate.com/service/translate/openai.html | 已提示可能过时，不据此认定实时价格 |
| Pot官方仓库 | https://github.com/pot-app/pot-desktop | Windows同类软件存在；不复用其代码 |
| CopyTranslator官方仓库 | https://github.com/CopyTranslator/CopyTranslator | 复制翻译已有产品 |
| CopyTranslator Windows说明 | https://copytranslator.github.io/download/windows.html | 确认Windows分发；页面较旧，不据此指定最新版 |
