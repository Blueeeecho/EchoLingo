# 初版独立只读审查记录

## 极简弹窗与换行专项复审（2026-10-24）

独立复审确认两项可复现问题并已关闭：Alt+A 在凭据编辑期间会把编辑器缩成 popup，现统一排队至编辑器关闭；普通无缩进函数调用/赋值/注释可能被误合并，现增加明确代码语法保护与反例测试。原文恢复仅对捕获内容显示，手输/粘贴/历史不走自动整理。单窗口使用独立管理/弹窗模式，fit 请求串行处理且测量当前DOM，不用焦点改变触发隐藏。

45 项前端、30 项 Rust 和隔离 IPC 回归通过；run 40102326336 的 Windows/macOS 构建、Windows 原生 OCR 几何与选区/剪贴板冒烟均通过。用户已在更新后的 macOS 独立 App 中按 Alt+D 确认极简弹窗生效。Windows 多屏和真实目标应用仍按手动计划验收，不能用浏览器布局夹具代替。

## 最新配置专项复审（2026-10-24）

供应商配置上线前，独立代理发现同一服务 ID 更换供应商后可能沿用旧密钥。现已在系统凭据内绑定协议及规范化 origin，并通过后端与前端回归验证跨域、跨协议、不同端口不能复用，同源路径或模型变化可以保留。百度/腾讯使用完整双凭据包；原生 JSON 格式化换行在保存与识别路径保持一致，字段值仍拒绝控制字符。专项复审未发现新增可复现阻塞问题。

28 项 Rust、20 项前端及隔离 IPC 用例通过。腾讯使用官方公开虚构凭据的完整 TC3 签名向量，百度使用本地 HTTP token/表单夹具；不将此写成真实云账户验收。Windows run 40097272065 的真实选区/空选区/剪贴板冒烟通过，仍不覆盖用户目标应用或多屏。

下文是历次审查的原始记录：R7 截断结果、R9 历史字节预算与 ID、R11 异步保存重入已修复并有对应回归。R6 隐藏/清空不取消已发网络任务、R10 某些协议的简繁目标映射及 R12 原生浮层焦点组合仍需继续改进或实机验证，不应把旧条目整体当作当前未修复清单。

日期：2026-10-24；同日完成第二轮复审。范围：`src-tauri/src/main.rs`、`model.rs`、`translation.rs`、`platform.rs`、前端 `src/main.ts` 与相关配置。初审行号可能因格式化而变化，下方修复证据给出复审位置。

本审查者已执行：`npm run check`，TypeScript 检查通过。其他代理的 Rust/原生验证请见 `docs/test-report.md`、`docs/native-testing.md`；本审查者没有独立运行 Windows 原生交互。本次仅改审查文档。

## 复审结论与关闭状态

五项原 P1 均已核实代码修复，关闭原缺陷；“关闭”不表示 Windows 实机测试已经通过。下一步按 `docs/windows-test-plan.zh-CN.md` 执行原生回归。

| 项目 | 状态 | 复审证据 |
|---|---|---|
| R1 Windows数据替换 | 源码修复关闭 | `main.rs:40` 写临时文件并 `sync_all`；59–72 行使用同卷 `MoveFileExW(REPLACE_EXISTING / WRITE_THROUGH)`，没有先删除正式文件 |
| R2 DeepL路径 | 源码修复关闭 | `translation.rs:9` 根路径补 `/v2/translate`；前端 `main.ts:366` 默认包含 `/v2`；完整路径不再重复追加 |
| R3 输入快捷键 | 源码修复关闭 | `src/main.ts:611` 监听 `focus-input`，切到翻译页并在下一帧聚焦；612 行监听 `ocr-copied` |
| R4 历史写入失败吞结果 | 源码修复关闭 | `main.rs:237` 成功写入才替换内存；失败存入诊断 warning，244 行仍返回译文 |
| R5 Tokio异步测试feature | 源码修复关闭 | `Cargo.toml` 显式加入 `macros` 与 `rt-multi-thread` |
| R8 提示词变量说明 | 源码修复关闭 | `index.html` 已只宣传 `{source}`、`{target}`，与后端一致 |

R1 的修复解决“主动删除正式文件造成数据缺口”，不等同承诺硬盘/文件系统/断电永不丢数据；故障注入与实际 Windows 文件锁回归仍需执行。R4 的 warning 目前在诊断页可见，运行中的明显提示可以继续改进。

## 原高优先级发现与修复背景

### R1 / 原 P1，已关闭：Windows 的 JSON 替换存在丢失设置与历史的崩溃窗口

位置：`src-tauri/src/main.rs:24`，尤其原 28–31 行；启动读取原 202–206 行。

Windows 路径先把旧文件复制到 `.json.bak`，再删除正式文件，再 rename 临时文件。若删除后崩溃、系统中断或 rename 失败，正式文件已不存在。启动仅读取正式文件，未恢复 `.bak` 或 `.tmp`，所以用户会看到默认配置/空历史；下一次写入可能覆盖恢复材料。存在备份文件本身不足以保证可恢复。

建议：使用 Windows 原子替换机制，并给临时文件写入 flush/sync；或至少做严格恢复流程，优先验证新临时文件、其次有效备份，保留坏文件。应做“替换前失败、删除后失败、rename失败、重启恢复”的故障注入测试。

### R2 / 原 P1，已关闭：默认 DeepL 配置生成错误 API 路径

位置：`src/main.ts:365` 默认 `https://api-free.deepl.com`，370 行说明无需 `/v2/translate`；`src-tauri/src/translation.rs:9` 只追加 `/translate`。

按界面默认值配置 DeepL，最终 URL 是 `https://api-free.deepl.com/translate`，缺少 `/v2`，无法正常翻译。官方接口是 `/v2/translate`。[DeepL 官方请求文档](https://developers.deepl.com/api-reference/translate/request-translation)

建议：以服务类型实现完整路径规范化，覆盖根地址、`/v2`、完整 `/v2/translate` 和末尾斜杠；在本地 Mock HTTP 测试中断言实际请求路径。

### R3 / 原 P1，已关闭：输入翻译快捷键没有对应前端事件监听

位置：`src-tauri/src/main.rs:137` 发送 `focus-input`；`src/main.ts:559` 开始的监听注册仅处理 `source-text`、错误事件。

按输入快捷键只会激活主窗口。若之前停留设置/历史页，仍停留原页面，也没有把焦点移至输入框，不能完成“快捷键→直接输入”的核心任务。

建议：监听 `focus-input`，切换翻译页并聚焦原文输入框；同时监听 `ocr-copied` 提供静默 OCR 成功反馈。测试应从隐藏窗口、设置页、历史页三种状态触发输入命令。

### R4 / 原 P1，已关闭：历史保存失败会掩盖已经成功取得的译文

位置：`src-tauri/src/main.rs:101`–110，原 107 行 `write_json(...)?`。

API 已成功返回，若磁盘满、权限变化或本地文件被占用，写历史失败会让整个 `translate` invoke 返回错误，前端丢失所有可用译文并显示“翻译失败”。再次重试会重复消耗 API 额度；持久化失败不应让本次翻译不可读。

建议：先交付翻译结果，将历史失败作为独立警告；只有成功写入后才更新内存持久化状态。测试用不可写目录模拟，断言译文仍返回且有存储警告。

### R5 / 原 P1，已关闭：异步测试依赖没有显式启用 Tokio macros

位置：`src-tauri/Cargo.toml:21` 只列 `time`、`sync`；`src-tauri/src/translation.rs:103` 使用 `#[tokio::test]`。

Tokio 的测试属性需要 `macros` 与 `rt`。[Tokio 文档](https://docs.rs/tokio/latest/tokio/attr.test.html) 已查看的 Tauri 常规依赖和 single-instance 不启用 macros。即使某个未来传递依赖偶然启用，也不应让测试构建依赖这种偶然性。

建议显式启用所需 feature 并运行 `cargo test`。这项是测试构建风险，不能以 TypeScript 通过代替 Rust 验证。

## 已发现且审查期间已得到处理的事项

- `main.rs` 原 31、33 行尾表达式 `map_err` 返回 `&str`，函数声明错误类型为 `String`，属于确定 Rust 类型不匹配；随后复读已看到 `.to_string()`。`set_api_key` 使用 `.into()` 无此问题。
- 窗口内“划词翻译”按钮最初会在 EchoLingo 自己聚焦时调用选文 helper；当前 `src/main.ts:441` 已改成提示用户在其他应用中按全局快捷键，避免读错来源。
- 前端使用 generation 序列号（193–225）过滤旧响应，来源输入改变也使结果失效；这能避免旧结果覆盖新结果，但不等于取消后端 API 请求。
- 确认当前 `GlobalHotKeyEvent` 有 `state()` 方法，`main.rs` 不是因为使用该方法而编译失败。依据为 [官方源码](https://github.com/tauri-apps/global-hotkey/blob/dev/src/lib.rs)。

## 中优先级与发布措辞限制

### R6 / P2：前端失效不取消网络任务，也不阻止旧任务写历史

`src/main.ts:136` / `193` 的 generation 只屏蔽 UI。后端 `main.rs:90`–110 无取消 ID，两个请求可并发执行到结束。修改原文、清空界面或 Esc 隐藏后，旧请求仍可能计费并写历史。还可出现“关闭历史保存后，较早启动的任务仍按旧 settings.save_history 保存”的行为。

建议：首版明确不宣称取消；如增加取消，需把任务 ID 和取消令牌传到后端，并在提交历史前检查当前隐私配置/取消状态。用延迟 Mock API 测试。

### R7 / P2：截断回复被作为完整翻译展示

`translation.rs:38`–45 只检查 `message.content`，不处理 `finish_reason=length` 或内容过滤。长译文可能被截断却显示“翻译完成”并存成功历史。

建议：明确识别截断/过滤并提示，保留可读的部分结果；添加对应响应夹具测试。

### R8 / 原 P2，已关闭：自定义提示词说明与实现不一致

`index.html` 提示支持 `{text}`；`translation.rs:27` 只替换 `{source}`、`{target}`，文本始终独立放在 user message。用户写了 `{text}` 会原样发送该占位符。

建议移除 `{text}` 的宣传并解释正文始终单独发送，或定义模板位置与转义契约。不要随意把不可信原文插进 system message。

复审：当前 `index.html` 已移除 `{text}` 的提示，与实现一致，此项关闭。

### R9 / P2：历史没有总字节预算

`model.rs:86` 允许 2000 条，响应每服务最多 2 MiB，最多 12 服务。极端情况下单条结果可达约 24 MiB，保存/clone/读取完整历史会远超轻量应用目标。`main.rs:104` ID 仅用毫秒时间和当前长度，在记录达到上限后也缺少严格唯一保证。

建议增加历史总字节上限、单条保留上限和独立唯一 ID；超大文本列表摘要化。优先测试2000条时的启动与搜索性能。

### R10 / P2：简繁中文的供应商映射丢失差异

`translation.rs:16` / 21 把 `zh-Hans`、`zh-Hant` 合并；界面提供“繁體中文”但某些引擎实际上无法返回该目标。建议按供应商当前语言能力单独映射，缺能力时明确提示，避免静默替换为简体。

## 新 fixed overlay 的安全与焦点复审

检查位置：`src/main.ts:375`–406（浮层显示/关闭）、438–471（异步保存）、530/565（遮罩关闭）、566–579（键盘约束）、606–612（原生事件）；`index.html:85`–86 和 `src/styles.css:109`–112。

已确认的改进：浮层位于 `.app-shell` 外，使用 `role=dialog`、`aria-modal` 与命名；显示后背景设为 inert/aria-hidden，Tab/Shift+Tab 会在可见可用控件内循环，Esc走统一关闭；关闭会恢复可见的先前焦点或导航后备焦点；全局 `[hidden]` 强制隐藏，关闭后的遮罩不会仍占据页面。服务名/错误/译文仍走 textContent，未引入远程 HTML 渲染。`closeProviderDialog` 会清空密码输入，浏览器预览不保存真实密钥。

### R11 / P2，待改进：异步保存期间关闭浮层后存在重入

位置：`src/main.ts:454`–469，仅禁用保存按钮；关闭按钮、取消、遮罩点击和Esc仍可关闭。旧 `saveProvider` 的 await 返回后，会写 `editingProviderId`、刷新设置并无条件 `closeProviderDialog()`。

复现：保存服务时人为延迟IPC/凭据库操作，立即按Esc或点遮罩；再打开另一个服务编辑，输入新的内容。前一个保存继续完成时，可能关闭新表单并清除其密码字段。已发出的保存也不会因用户按“取消”撤回。现有代码使用函数捕获的 provider ID/key，未发现把旧key错存到新provider的直接路径，但会造成编辑内容丢失和操作含义不清。

建议：保存期间禁用关闭/编辑，或给每次浮层会话分配token，旧异步任务只能更新自己的会话；若允许关闭，明确“保存继续”并确保旧任务不能关闭新窗口。把延迟保存→关闭→再打开加入回归。

### R12 / P2，待实机验证：全局事件与浮层的焦点冲突

`focus-input` 和 `source-text` 事件没有先检查浮层是否开启。设置浮层尚未关闭时，用户切到其他软件并触发快捷键，回到EchoLingo会留下浮层；事件同时切换背景页、修改来源文本，尝试把焦点送入 inert 的原文区。在较旧WebKit没有完整inert支持时，程序化focus可能绕过Tab约束；Windows/WebView2也应验证当前焦点是否仍留在活动浮层。

建议：活动浮层开启时，将原生输入事件排队，或明确关闭浮层后再处理；不要悄悄丢弃用户正在填写的配置。还需在系统凭据库弹窗导致主窗口失焦时验证内容保留与恢复。此项目前是代码可达的交互风险，尚无原生运行失败证据。

## 安全方面的正面观察与未验证边界

- 未发现将 API key 序列化进设置/历史的直接代码；凭据通过 keyring 存储。
- 上游错误不原样返回正文，降低代理回显密钥/原文的风险。
- 结果、历史、错误和名称通过 textContent 构建，没有看到把上游译文塞进 innerHTML 的路径。
- 远程 API 要求 HTTPS，本机 HTTP 例外；禁重定向，避免自动把 Authorization 跟到其他主机。
- 这些观察不构成全面安全审计；实际 Keychain/Credential Manager、截图权限、辅助功能、选文焦点、PowerShell/WinRT 和混合 DPI 仍需原生测试。
