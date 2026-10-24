# 初版独立只读审查记录

日期：2026-10-24。范围：`src-tauri/src/main.rs`、`model.rs`、`translation.rs`、`platform.rs`、前端 `src/main.ts` 与相关配置。此文件是开发中的快照，行号对应审查时版本；修复需要重新验证，不能把它当最终未解决列表。

已执行：`npm run check`，TypeScript 检查通过。没有本机 Rust 编译结果；未运行 Windows 原生交互。本次未修改实现文件。

## 高优先级发现

### R1 / P1：Windows 的 JSON 替换存在丢失设置与历史的崩溃窗口

位置：`src-tauri/src/main.rs:24`，尤其原 28–31 行；启动读取原 202–206 行。

Windows 路径先把旧文件复制到 `.json.bak`，再删除正式文件，再 rename 临时文件。若删除后崩溃、系统中断或 rename 失败，正式文件已不存在。启动仅读取正式文件，未恢复 `.bak` 或 `.tmp`，所以用户会看到默认配置/空历史；下一次写入可能覆盖恢复材料。存在备份文件本身不足以保证可恢复。

建议：使用 Windows 原子替换机制，并给临时文件写入 flush/sync；或至少做严格恢复流程，优先验证新临时文件、其次有效备份，保留坏文件。应做“替换前失败、删除后失败、rename失败、重启恢复”的故障注入测试。

### R2 / P1：默认 DeepL 配置生成错误 API 路径

位置：`src/main.ts:365` 默认 `https://api-free.deepl.com`，370 行说明无需 `/v2/translate`；`src-tauri/src/translation.rs:9` 只追加 `/translate`。

按界面默认值配置 DeepL，最终 URL 是 `https://api-free.deepl.com/translate`，缺少 `/v2`，无法正常翻译。官方接口是 `/v2/translate`。[DeepL 官方请求文档](https://developers.deepl.com/api-reference/translate/request-translation)

建议：以服务类型实现完整路径规范化，覆盖根地址、`/v2`、完整 `/v2/translate` 和末尾斜杠；在本地 Mock HTTP 测试中断言实际请求路径。

### R3 / P1：输入翻译快捷键没有对应前端事件监听

位置：`src-tauri/src/main.rs:137` 发送 `focus-input`；`src/main.ts:559` 开始的监听注册仅处理 `source-text`、错误事件。

按输入快捷键只会激活主窗口。若之前停留设置/历史页，仍停留原页面，也没有把焦点移至输入框，不能完成“快捷键→直接输入”的核心任务。

建议：监听 `focus-input`，切换翻译页并聚焦原文输入框；同时监听 `ocr-copied` 提供静默 OCR 成功反馈。测试应从隐藏窗口、设置页、历史页三种状态触发输入命令。

### R4 / P1：历史保存失败会掩盖已经成功取得的译文

位置：`src-tauri/src/main.rs:101`–110，原 107 行 `write_json(...)?`。

API 已成功返回，若磁盘满、权限变化或本地文件被占用，写历史失败会让整个 `translate` invoke 返回错误，前端丢失所有可用译文并显示“翻译失败”。再次重试会重复消耗 API 额度；持久化失败不应让本次翻译不可读。

建议：先交付翻译结果，将历史失败作为独立警告；只有成功写入后才更新内存持久化状态。测试用不可写目录模拟，断言译文仍返回且有存储警告。

### R5 / P1：异步测试依赖没有显式启用 Tokio macros

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

### R8 / P2：自定义提示词说明与实现不一致

`index.html` 提示支持 `{text}`；`translation.rs:27` 只替换 `{source}`、`{target}`，文本始终独立放在 user message。用户写了 `{text}` 会原样发送该占位符。

建议移除 `{text}` 的宣传并解释正文始终单独发送，或定义模板位置与转义契约。不要随意把不可信原文插进 system message。

### R9 / P2：历史没有总字节预算

`model.rs:86` 允许 2000 条，响应每服务最多 2 MiB，最多 12 服务。极端情况下单条结果可达约 24 MiB，保存/clone/读取完整历史会远超轻量应用目标。`main.rs:104` ID 仅用毫秒时间和当前长度，在记录达到上限后也缺少严格唯一保证。

建议增加历史总字节上限、单条保留上限和独立唯一 ID；超大文本列表摘要化。优先测试2000条时的启动与搜索性能。

### R10 / P2：简繁中文的供应商映射丢失差异

`translation.rs:16` / 21 把 `zh-Hans`、`zh-Hant` 合并；界面提供“繁體中文”但某些引擎实际上无法返回该目标。建议按供应商当前语言能力单独映射，缺能力时明确提示，避免静默替换为简体。

## 安全方面的正面观察与未验证边界

- 未发现将 API key 序列化进设置/历史的直接代码；凭据通过 keyring 存储。
- 上游错误不原样返回正文，降低代理回显密钥/原文的风险。
- 结果、历史、错误和名称通过 textContent 构建，没有看到把上游译文塞进 innerHTML 的路径。
- 远程 API 要求 HTTPS，本机 HTTP 例外；禁重定向，避免自动把 Authorization 跟到其他主机。
- 这些观察不构成全面安全审计；实际 Keychain/Credential Manager、截图权限、辅助功能、选文焦点、PowerShell/WinRT 和混合 DPI 仍需原生测试。

