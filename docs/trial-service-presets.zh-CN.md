# 新人试用模型预设（核对日期：2026-10-30）

此批只新增标准 OpenAI Chat Completions 兼容预设，Windows/macOS 共用既有传输、凭据与取消逻辑。没有改动或删除用户已保存的自定义端点、模型和 Key。新人试用不是永久免费，不与官方机器翻译或订阅套餐混淆。

| 平台 | 标准地址 / 文档示例模型 | 额度条件 |
| --- | --- | --- |
| 百度千帆 | `https://qianfan.baidubce.com/v2` / `ernie-4.5-turbo-128k` | 首次开通指定预置模型各 100 万 Token，有效 3 个月；仅在线推理，不包含批量 |
| 腾讯 TokenHub 中国站 | `https://tokenhub.tencentmaas.com/v1` / `hy3` | 新人语言模型体验 100 万 Token，有效 1 年；主账号共享、不可叠加，每账号每模型限领取一次，本期领取活动截至 2026-12-31 |
| 火山方舟北京 | `https://ark.cn-beijing.volces.com/api/v3` / `doubao-seed-2-1-pro-260915` | 有新人试用，但各模型数量、期限以开通管理为准，不硬编码旧活动统一赠送量 |

模型 ID 是官方文档中的可编辑示例，不保证当前账号有资格、余额或调用权限。为避免用示例直接消耗付费额度，**试用向导必须手动填写账号中已确认有免费余额的模型 ID**，留空不会创建服务或发送测试。测试仅使用内置短句，不读取用户选区。

TokenHub 按中国站日期（UTC+8），到本期领取截止日期后从“新用户免费推荐”隐藏，但保留预设、已保存配置和已领取的额度使用途径。仅匹配标准地址时才推断这些试用预设；不会将同域名的 `/plan/v3` 订阅端点标成新人免费体验。

验证范围：预设与路径区分、配额期限/共享文案、试用模型确认、无密钥写入设置、仅启用所选翻译而不改变 OCR、推荐到期隐藏。无真实账号/API Key 调用；协议与额度公开文档核验不等于真实账户实测。

## 官方依据

- [千帆 OpenAI 兼容](https://ai.baidu.com/ai-doc/WENXINWORKSHOP/2m3fihw8s)、[模型列表 API](https://cloud.baidu.com/doc/qianfan-api/s/Dmba8k71y)、[新人额度](https://cloud.baidu.com/doc/qianfan/s/Imi2rpirg)
- [TokenHub 语言模型接口](https://cloud.tencent.com/document/product/1823/130079)、[API 与模型 ID](https://cloud.tencent.com/document/product/1823/130078)、[新人体验规则](https://cloud.tencent.com/document/product/1823/130053)
- [方舟文本生成与模型示例](https://docs.volcengine.com/docs/ark/text-generation)、[当前新人额度规则](https://console.volcengine.com/ark/region:cn-beijing/docs/free-inference-quota)

第一批 Gemini/Groq/Ollama 与第二批小牛/Google NMT/彩云在独立 PR，集成时保留它们和翻译/OCR 折叠列表。未确认统一免费资格的 AWS、付费 OCR、词典不在本批，不能把它们标为已免费适配。
