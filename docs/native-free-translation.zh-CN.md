# 新增官方机器翻译适配器（2026-10-30）

Windows 与 macOS 使用同一份 Rust 协议实现；新服务默认不会替换或启用已有配置。免费列表中的“测试并启用”先发送内置测试短句，成功后仅启用所选服务；OCR 不跟随改变。用户需自己申请 Key，密钥仍由系统凭据库保存，不写入设置或日志。

| 服务 | 接口与认证 | 免费规则 |
| --- | --- | --- |
| 小牛翻译 | 固定 HTTPS `api.niutrans.com/NiuTransServer/translation`，POST 表单，Key 在请求体 | 注册账户每日 20 万字符（100 积分），非每月累计；账号积分和限速以控制台为准 |
| Google Cloud Translation | Basic v2 NMT；固定 `translation.googleapis.com/language/translate/v2`；`X-Goog-Api-Key` 请求头，不放 URL | Basic/Advanced 共用每月前 50 万字符、最多 10 美元抵扣，不结转；需 API 与结算，超额可能收费 |
| 彩云小译 | 固定 `api.interpreter.caiyunai.com/v1/translator`；`X-Authorization: token …` | 新用户一次 100 万字符，有效 1 个月；不是按月刷新，字符含空格和标点 |

## 安全与限制

- 不接受原生服务的代理、自定义域名、路径、查询密钥或 HTTP；共用禁止重定向的客户端。
- 每次请求 45 秒超时、响应最多 2 MiB；无自动重试、无计费分片、无脱离调用者的后台请求，取消时丢弃请求 future。
- 小牛采用应用保守单次上限 5,000 UTF-8 字节；Google/彩云应用保守单次上限 5,000 Unicode 字符。不是宣称厂商统一硬上限。
- 小牛当前只映射已核对语言，不冒充支持繁体中文。彩云只接受官方矩阵中的中外互译和允许的自动源语言方向，不将英日互译宣称为支持。
- Google 的 403 可能是权限或额度，不统一误报为密钥错误。厂商响应可能包含 Key 或原文，因此只返回应用固定错误说明，不透传厂商错误文本。
- 不使用公开测试 Token、其他软件的内置 Key、第三方免 Key 代理。Google Cloud Translation 不是 Gemini，彩云不是每月赠送额度。

## 验证边界

覆盖协议合成 HTTP 请求、认证位置、源语言省略与映射、成功/错误/空/数量不一致响应、错误脱敏、拒绝重定向、响应上限、取消无重试、凭据命名空间、端点限制、向导独立启用和设置无密钥。

没有真实账户/Key，也没有消耗真实 API 额度：协议 fixture 测试不是账户可用性实测。完整平台应用构建与回归由 Windows/macOS CI 验证；用户账户资格、网络地域、模型或套餐可用性仍需在应用中测试连接。

## 官方来源

- [小牛每日额度](https://niutrans.com/text_trans)、[小牛 API](https://niutrans.com/documents/contents/trans_detection)
- [Google NMT 价格](https://cloud.google.com/products/translate/pricing)、[Basic v2 参数](https://docs.cloud.google.com/translate/docs/reference/rest/v2/translate)、[官方 Key 请求头示例](https://docs.cloud.google.com/docs/authentication/api-keys-use)
- [彩云接口、语言矩阵与试用额度](https://docs.caiyunapp.com/lingocloud-api/index.html)

兼容模型预设（Gemini/Groq/Ollama）在独立 PR 中处理。千帆、TokenHub、方舟新人额度下一批核对后适配；AWS 新旧免费计划资格未确认，付费 OCR 与词典不在本批内。

小牛错误分类复核：官方 `trans_detection` 文档搜索索引于 2026-10-30 可读取（页面直接打开间歇超时）。13001 表示流量不足或权限受限；13002 表示 Key 参数缺失；10001 为请求频率、10003 为长度、13007 为语言、13008 为处理超时。未知码使用通用错误，不猜测账户状态。
