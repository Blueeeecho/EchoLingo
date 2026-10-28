# 官方翻译与 OCR 服务配置

2026-10-28 源码说明。是否已包含这些入口，以所安装预览包的版本说明为准。新增协议使用了本地模拟 HTTP、虚构凭据与界面回归测试；尚未使用真实厂商账户验收，不能据此保证账号已开通或有可用额度。

## 选择与配置

在托盘菜单打开“设置与服务”。翻译服务按本机、官方机器翻译、大模型兼容分组；添加新服务默认选百度通用文本翻译。原有服务及新安装时的本机翻译默认不会因此更改。

1. 选择供应商，使用表单中的开通、控制台、API 文档链接取得该产品对应的凭据。
2. 完整填写服务的专属字段并保存。编辑已有服务时，全部凭据字段留空会保留匹配当前协议、地址的已存凭据；替换成对凭据时须同时填写两项。
3. 主动点击服务测试，确认该账号的服务权限、地域、网络和额度。普通状态刷新不会读取系统凭据或重新发起认证。

文档链接在系统默认浏览器打开。它们是应用内置的固定链接，不会把密钥、原文或截图拼到 URL 中。

## 官方机器翻译

| 服务 | 配置字段 | 需要注意 |
|---|---|---|
| 百度通用文本翻译 | APP ID、密钥 | 使用翻译开放平台的凭据，不是百度 OCR 的 API Key。固定通用文本翻译端点，按厂商要求计算 MD5 请求签名。 |
| 有道文本翻译 | 应用 ID（AppKey）、应用密钥（AppSecret） | 应用须关联文本翻译服务。固定端点、v3 SHA-256 签名，严格遵守选择的目标语言。 |
| Microsoft Translator | 资源密钥、按需填写地域 | 当前支持公共全球端点的 API Key 认证；地域/多服务资源需填写资源地域，全球单服务资源可留空。不支持 Azure 中国区或私有端点。 |
| DeepL API | DeepL API Key、Free/Pro 对应地址 | 普通网页翻译订阅与 API 套餐不同。 |
| LibreTranslate | 所选实例地址、按实例要求填写 Key | 可使用自己部署的实例；是否收费或要求密钥由实例运营方决定。 |

新增三项官方适配器不使用聊天模型名、Prompt 或通用 Bearer 模板。其响应为完整译文；支持流式输出的大模型兼容服务继续按原流程工作。

默认中英互译及手动指定语言继续有效。当前适配器仅映射界面支持的语言，超出范围会明确报错。百度单次采用保守的 6,000 UTF-8 字节上限，有道为 5,000 字符；套餐可能有更小限制。应用不会自动拆分或重试付费请求。

官方资料：[百度通用翻译](https://fanyi-api.baidu.com/doc/21)、[有道文本翻译](https://ai.youdao.com/DOCSIRMA/html/trans/api/wbfy/index.html)、[Microsoft 翻译](https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/v3/translate)、[Microsoft 认证和地域](https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/authentication)、[DeepL](https://developers.deepl.com/api-reference/translate/request-translation)、[LibreTranslate](https://docs.libretranslate.com/guides/api_usage/)。

阿里百炼/Qwen 保留在大模型兼容分组；它不等于阿里机器翻译。此次未宣称实现阿里机器翻译、腾讯旧文本翻译或 Bob 插件兼容。

## OCR

默认仍是本机离线 OCR。添加云服务不会自动切换识别方式；只有明确选中该 OCR 服务并执行截图识别，图片才会发送到它的固定官方端点。本机失败不会静默上传。

| 服务 | 配置字段 | 协议/动作 |
|---|---|---|
| 百度 OCR | API Key、Secret Key | 换取访问令牌，再调用通用或高精度识别。 |
| 腾讯 OCR | SecretId、SecretKey、可选 SessionToken、地域 | TC3 请求签名，通用或高精度识别。 |
| 有道通用 OCR | AppKey、AppSecret | `https://openapi.youdao.com/ocrapi`，v3 签名表单，保留识别行及区域段落。 |
| Google Cloud Vision | 原始 API Key | `https://vision.googleapis.com/v1/images:annotate`；默认 `DOCUMENT_TEXT_DETECTION`，也可选 `TEXT_DETECTION`。Key 使用请求头发送，不放进 URL。 |

Google Cloud 项目需启用 Vision API 并按控制台要求配置结算及 API Key 限制。当前不接受服务账号 JSON 或 OAuth Bearer 凭据。

有道图片仍须满足厂商尺寸要求（最长边小于 2048、最短边大于 10）；厂商可能对较大图片做处理。应用只校验 Base64 和保守的完整编码表单 4 MB 上限，不自动缩放，也未进行像素尺寸预检查。Google 完整 JSON 请求采用 10 MB 上限。超过限制会提示缩小截图；不自动改用其他服务。

官方资料：[有道通用 OCR](https://ai.youdao.com/DOCSIRMA/html/ocr/api/tyocr/index.html)、[Google OCR](https://cloud.google.com/vision/docs/ocr)、[Google API Key](https://cloud.google.com/docs/authentication/api-keys-use)。已有视觉大模型及 JSON 网关设置继续保留，见[自定义 OCR](custom-ocr.md)。

## 凭据与数据

新增的官方翻译与 OCR 协议使用彼此独立的系统凭据账户和用途范围，避免同厂商服务意外共用密钥；旧协议的已保存账户保持兼容。

设置文件仅保存服务类型、公共地址、动作、地域等配置。密钥进入系统凭据库，读取结果只在本次运行的受控内存中缓存；缺失或拒绝也会缓存，普通翻译不会循环索取认证。需要重试时在设置中主动操作。

OCR 图片与识别文字的去向不同：云 OCR 获得所选区域图片；启用的云翻译服务获得识别文字。选择本机 OCR 加云翻译，仍会发送文字。请根据处理内容选择服务。
