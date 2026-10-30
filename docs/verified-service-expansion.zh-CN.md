# 服务扩展核对（2026-10-30）

服务推荐不代表无限免费，也不继承其他软件提供的内置密钥或代理。
以下新增项复用 Windows/macOS 的同一兼容协议实现，不更改已有服务地址、模型、启用状态或密钥。

## 第一批：可配置的兼容预设

| 服务 | 接口/额度 | 说明 |
| --- | --- | --- |
| Gemini | [OpenAI 兼容](https://ai.google.dev/gemini-api/docs/openai)；[指定模型免费层](https://ai.google.dev/gemini-api/docs/pricing) | 示例 `gemini-3.8-flash`；账号、地域和模型限速；免费层内容可能用于改进产品 |
| Groq | [OpenAI 兼容](https://console.groq.com/docs/openai)；[Free tier](https://console.groq.com/docs/billing-faqs) | 示例 `openai/gpt-oss-20b`；不承诺统一月度 Token 数，[限速](https://console.groq.com/docs/rate-limits)以账号为准 |
| Ollama | [本机兼容 API](https://docs.ollama.com/api/openai-compatibility) | 需自己安装服务和下载模型；向导填写本机模型，无需 Key；云模型和远程服务不属于本机免费推理 |

验证边界：已核对官方公开协议；单元测试覆盖预设、向导独立启用、无 Key 本机配置、失败回滚及既有配置保留。没有使用真实账号、真实 Key 或安装好的 Ollama 做端到端调用，不能将协议测试称为账户实测。首次启用仍须由用户在应用中测试连接。

## 后续分批范围（尚不宣称已适配）

- 小牛：官方专用接口；每日 20 万字符（100 积分），待原生协议适配和测试。
- Google Cloud Translation NMT：官方原生接口；Basic/Advanced 共用每月前 50 万字符的最多 10 美元抵扣，待适配。不是 Gemini。
- 彩云小译：专用接口；新用户一次 100 万字符、有效 1 个月，待适配。
- 千帆、TokenHub、方舟：新人试用须另列期限和账号条件，待精确模型与接口校验后添加，不伪装为长期免费。
- AWS Translate：新旧免费计划资格需确认；付费 OCR、词典资源不属于本批免费接口扩展。

腾讯旧文本/图片翻译、金山、零一万物不加入新用户推荐；它们不在现有内置推荐列表，无须删除用户自定义配置。已有腾讯 OCR 是不同产品，继续保留。
