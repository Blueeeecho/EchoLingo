# EchoLingo API 与 OCR 配置设计：以 Bob 官方文档为参照

2026-10-28 更新：下文保留 10 月 24 日的研究与实现快照。新增百度、有道、Microsoft 文本翻译及有道、Google OCR 的当前协议、凭据与配置入口见[官方服务配置说明](official-services.zh-CN.md)；源码支持不等于真实厂商账户已验收。

原始研究及访问日期：2026-10-24。该轮只查阅 Bob、供应商官方文档及官方 SDK；未读取本机 Bob 配置或系统钥匙串，未取得、验证或迁移任何用户密钥，未调用真实云 API。2026-10-25 经授权进行的 MiniMax 实测另见下节。供应商页面会更新，端点、模型、价格、额度均须以开户地区和控制台为准。

本文区分三类信息：**官方已确认**表示页面或官方 SDK 明示的行为/协议；**设计建议**表示 EchoLingo 应采用的产品方案；**实现快照**表示本次查阅的仓库状态，不能代替实机或真实账户验收。

## MiniMax 中国站：2026-10-25 实测补充

文本翻译可选新增的「MiniMax · 中国站」预设，协议为 OpenAI 兼容，Base URL 为 `https://api.minimax.cn/v1`，模型为 `MiniMax-M3.1-Flash`，模型名称仍可编辑。填写与中国站地域/账号匹配的 Key，正常使用时由 EchoLingo 保存到系统凭据库。订阅 Key 与普通按量 Key 的额度规则不同，按官方账号说明配置。[OpenAI 兼容协议](https://platform.minimax.cn/docs/api-reference/text-openai-api)、[订阅及地域说明](https://platform.minimax.cn/docs/m-plan/faq)。

图片识字使用「OpenAI 兼容 Vision」类型，填写相同 Base URL 和模型，保持认证头 `Authorization`、前缀 `Bearer ` 与默认识字提示词。保存后仍需明确选择该 OCR 服务，截图才会上传；本机 OCR 默认值不会被改动。模型支持原生 `image_url` 图片输入，思考与最终文本分别返回；M3.1 Flash 默认思考深度为 max，不能关闭思考。[官方模型调用](https://platform.minimax.cn/docs/guides/text-generation)。

本次已用生产代码实测七次文本/生成图请求，详细边界和结果见 [测试报告](test-report.md)。凭据仅供本轮内存测试，未预填到任何文件或应用，也未上传 GitHub；这不等于已完成安装版界面验收。

## 1. 结论与首版边界

应学习 Bob 的“按能力配置服务”，把**文本翻译、文字识别、语音朗读**分开管理；每条服务拥有自己的凭证、配置和状态。普通用户选择供应商预设并填写对应字段，高级用户才进入 OpenAI 兼容端点或 JSON 网关。不能把所有供应商简化为一个“API Key”输入框。

翻译可以同时启用多家并按用户顺序展示；OCR 默认使用本机引擎，每次明确选择一个主引擎。**单 OCR 主选择是 EchoLingo 的设计建议，并非据此断言 Bob 的全部 OCR 路由实现。** 本机 OCR 失败时应说明语言包、权限或识别失败原因，云 OCR 只能由用户主动选择，不能静默上传作为兜底。语音服务另设入口，避免 OCR 配置被误用于 TTS。

实现快照：已实现本机 OCR、百度、腾讯、OpenAI 兼容视觉模型及 HTTP JSON 网关。百度 token/表单、腾讯 TC3 签名已有原生模块，专用凭据表单和协议测试已通过；**协议测试不等于真实云账户验收完成**。火山、有道尚不能因为有一个 JSON 模板编辑器就宣称原生支持；其签名仍需明确的原生适配器或用户自建网关。百度当前每次请求换取 token，内存 token 缓存属于后续性能改进。

## 2. Bob 的服务配置：已确认与可复用的交互

### 2.1 分类、添加、保存、启停与顺序

Bob 官方教程将服务分为文本翻译、文本识别、语音合成。翻译流程会用到这些能力，独立 OCR 也有自己的服务设置。服务来源包括内置免费服务、用户向厂商申请的个人凭证、插件扩展。添加路径为偏好设置的服务面板，点击 `+` 选择类型，填写所需凭证，可使用“验证”，再启用并保存；多个翻译服务的顺序可以拖动调整。[Bob：添加服务](https://bobtranslate.com/guide/advance/service.html)

服务管理面板在 Bob 1.20 有过调整；2026-10-24 查阅的更新日志最新条目为 1.21.2（2026-10-13）。因此网页旧截图只能说明流程，不能据截图推断当前按钮布局。当前快速入门说明最多同时使用 12 个翻译服务，也支持把服务固定为按需调用。[Bob：更新日志](https://bobtranslate.com/general/changelog.html)、[Bob：翻译入门](https://bobtranslate.com/guide/quickstart/translate.html)

顺序不仅影响视觉布局：Bob 的静默翻译替换使用第一个启用的翻译服务。EchoLingo 如果以后提供静默替换，应把“默认用于替换的服务”直接写明，不能让用户从排序规则猜测。[Bob：静默翻译](https://bobtranslate.com/blog/2025-08-11-silent-translate.html)

### 2.2 验证并不等于启用，也不等于永久可用

Bob 的排错文档分别讨论了凭证多粘空格/换行、多个凭证填错位置、服务未开通、额度或账户问题、系统时间和网络问题。它说明验证至少涉及“字段正确、服务开通、网络可达”等不同条件，不能把所有失败都显示成“密钥错误”。签名类服务尤其依赖时间。[Bob：服务密钥验证失败](https://bobtranslate.com/faq/service-error.html)

**设计建议：**“保存配置”“在线测试”“启用”是三个独立动作。保存只做本地结构校验；在线测试明确说明将发送一段示例文字或内置示例图片、可能消耗额度；测试成功后也不自动启用。允许先保存未测试配置，但状态必须标记“未测试”。修改端点、模型、地区、方法或任一凭证后，旧的成功结果应失效。禁用表示不参与正常任务，仍可显式测试。

### 2.3 插件与供应商凭证的关系

Bob 插件用 `.bobplugin` 包安装，安装后仍要添加并启用服务；插件元信息分别声明 `translate`、`ocr`、`tts` 类型与配置选项。插件是协议或功能扩展，不意味着获得免费供应商账户，也不意味着继承 Bob 的合作凭证。EchoLingo 首版不必运行第三方 JavaScript 插件，先把原生适配和无代码 JSON 网关做好。[Bob：插件使用](https://bobtranslate.com/guide/advance/plugin.html)、[Bob：插件元信息](https://bobtranslate.com/plugin/quickstart/info.html)

### 2.4 配额与费用展示

Bob 官方服务总览和申请教程包含免费额度、合作服务和历史价格说明，但这些不是 EchoLingo 用户账户的实时权益。服务可用性、API 权限、账户余额、免费资源包、QPS/速率限制、应用级限额应分别表示。Bob Pro 购买也不能被表述为向任意第三方 API 支付了费用。[Bob：服务总览](https://bobtranslate.com/guide/advance/service.html)

**设计建议：**无法查询配额时显示“未知／到供应商控制台查看”，不能显示 0 或“无限”。显示本地请求次数时注明它不是账单；并发翻译应说明一次操作会请求几家启用服务。只在供应商有正式查询接口且用户主动刷新时读取远程配额。

## 3. 翻译供应商：准确字段与端点

下表字段是**供应商 API 字段**及 EchoLingo 应采用的输入项，不是根据 Bob 截图臆测的当前 UI 字段名。模型 ID 不应写死为永久有效清单；预设可以提供访问日示例并允许手填。

| 预设 | 用户填写的凭证与参数 | 官方请求与鉴权 | 端点及地区边界 |
|---|---|---|---|
| OpenAI／OpenAI 兼容 | `API Key`、`Base URL`、`model`；提示词；OpenAI 特定组织/项目为高级可选项 | `Authorization: Bearer …`；Chat Completions 使用 `model`、`messages`、`stream`。兼容协议不等于完整实现 Responses API | OpenAI base 为 `https://api.openai.com/v1`，完整调用为 `/chat/completions`。第三方兼容端点由用户明确配置 |
| DeepSeek | 独立 DeepSeek API Key、`model`；可编辑 base | Bearer；官方支持 OpenAI 格式的 Chat API | 官方 base 为 `https://api.deepseek.com`，完整 `https://api.deepseek.com/chat/completions`。本次官方页面示例模型为 `deepseek-flash`、`deepseek-v4-pro`；不把旧模型名当成永久默认 |
| 智谱 BigModel | 独立 API Key、`model`、可编辑 base | Bearer；`model`、`messages` | `https://open.bigmodel.cn/api/paas/v4/chat/completions`。标准 API 与 Coding 套餐的 key/端点不能混用 |
| 硅基流动 SiliconFlow | 独立 API Key、供应商完整 `model` ID、可编辑 base | Bearer；`model`、`messages` | `https://api.siliconflow.cn/v1/chat/completions`；模型支持文本/视觉等能力须逐个确认，不能由账号能登录推定 |
| 阿里百炼／通义千问 | 百炼 API Key、地区、可选 `WorkspaceId`、`model`、可编辑 base | Bearer；OpenAI 兼容 `model`、`messages` | 当前推荐 `https://{WorkspaceId}.{region}.maas.aliyuncs.com/compatible-mode/v1/chat/completions`；官方列出 `cn-beijing`、`us-east-1`、`ap-southeast-1`、`ap-northeast-1`。key 必须匹配地区及计费计划 |
| DeepL API Free／Pro | **DeepL API** 的认证密钥；套餐 Free/Pro；可选自定义端点 | `Authorization: DeepL-Auth-Key …`；`text` 为数组，`target_lang` 必填，自动检测时省略 `source_lang` | Free：`https://api-free.deepl.com/v2/translate`；Pro：`https://api.deepl.com/v2/translate`。普通网页翻译订阅不能代替 API 产品 |

以上分别由官方文档确认：[OpenAI 鉴权与端点](https://developers.openai.com/api/reference/overview)、[OpenAI Chat Completions](https://developers.openai.com/api/reference/resources/chat)、[DeepSeek 首次调用](https://api-docs.deepseek.com/)、[智谱 API 总览](https://docs.bigmodel.cn/cn/api/introduction)、[智谱 OpenAI 兼容](https://docs.bigmodel.cn/cn/guide/develop/openai/introduction)、[硅基流动 Chat API](https://docs.siliconflow.cn/docs/api/chat-completions-post)、[百炼 OpenAI 兼容](https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope)、[百炼 Base URL](https://help.aliyun.com/en/model-studio/base-url)、[DeepL 鉴权](https://developers.deepl.com/docs/getting-started/auth)、[DeepL 快速开始](https://developers.deepl.com/docs/getting-started/quickstart)。

百炼旧北京端点 `https://dashscope.aliyuncs.com/compatible-mode/v1` 及旧新加坡 `https://dashscope-intl.aliyuncs.com/compatible-mode/v1` 仍见于官方兼容说明，适合兼容已有配置；新建配置优先提示地区/工作空间域名，勿把北京 key 自动发往新加坡。Coding Plan 等专用额度端点不应成为通用翻译默认值。Bob 的 Qwen-MT 专用翻译服务另有限制：更新日志明确它不支持自定义 Prompt；不能把所有千问服务都当作相同聊天模板。[百炼官方兼容说明](https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope)、[Bob 更新日志](https://bobtranslate.com/general/changelog.html)

### 3.1 “阿里翻译”必须与“阿里百炼”分开

Bob 的阿里翻译申请教程指向阿里机器翻译，使用 AccessKey 管理；它与百炼聊天模型不是同一项 API。[Bob：阿里翻译](https://bobtranslate.com/service/translate/ali.html)

阿里机器翻译应有单独预设，字段为 `AccessKeyId`、`AccessKeySecret`，以及地区、接口能力。当前 `alimt/2018-10-12` 官方 API 总览标注 **RPC 签名风格**，推荐使用官方 SDK。`TranslateGeneral` 需要 `FormatType`（`text`/`html`）、`SourceLanguage`、`TargetLanguage`、`SourceText`、`Scene=general`，可选 `Context`；结果位于 `Data.Translated`。杭州端点是 `mt.cn-hangzhou.aliyuncs.com`，新加坡为 `mt.ap-southeast-1.aliyuncs.com`，不能凭产品缩写猜出域名。[机器翻译 API 总览](https://help.aliyun.com/zh/machine-translation/developer-reference/api-alimt-2018-10-12-overview)、[TranslateGeneral](https://help.aliyun.com/zh/machine-translation/developer-reference/api-alimt-2018-10-12-translategeneral)、[接入点](https://help.aliyun.com/zh/machine-translation/developer-reference/api-alimt-2018-10-12-endpoint)

研究中还实际读到阿里机器翻译旧 ROA 签名文档，使用 `acs` 风格鉴权及 HMAC-SHA1，示例版本与上述 RPC 页面不同。**不能把旧 ROA 签名头与当前 RPC 参数混拼**。本报告不据此推断当前 RPC 适配已实现；后续须锁定一个 API 版本并通过官方 SDK/固定签名向量验证。[机器翻译旧签名页面](https://help.aliyun.com/zh/machine-translation/developer-reference/signature-mechanism)

### 3.2 模型翻译的共同设置

**设计建议：**常规页只显示服务名、凭证、模型、语言方向；高级页显示 Base URL、Prompt、超时和少量已支持参数。Prompt 变量需有明确清单及预览。保留“把输入当作待译内容”的系统约束，但不宣称提示词可以完全消除模型误译或注入。语义译文不得混入 reasoning 内容，截断、内容过滤、空内容应明确报错，不能显示为成功译文。

供应商“兼容”只说明指定 API 的字段和返回结构相近，并不保证每个模型都支持同一角色、参数、视觉或工具能力。获取模型列表可以作为可选功能，失败时仍允许手填；不应在编辑输入框时自动向外联网。API Key 只送到用户保存的指定服务端点，跨供应商切换应重新确认凭证状态，不能沿用上家的 key。

## 4. OCR 供应商：凭证与协议不能混用

### 4.1 百度：个人 API 与 Bob 内置试用必须区分

Bob 服务总览将“百度 OCR 试用版”列为无需自行申请、稳定性不作保证的内置试用；百度个人服务则要求用户自己开通 OCR、创建应用并取得应用凭证，免费资源包也可能需要另行领取。这两种使用路径不同，EchoLingo 不能复制、寻找或共享 Bob 的内置试用凭证，更不能宣称 Bob 的试用额度属于 EchoLingo 用户。[Bob：服务总览](https://bobtranslate.com/guide/advance/service.html)、[Bob：百度 OCR 申请](https://bobtranslate.com/service/ocr/baidu.html)

| 项目 | 官方已确认 |
|---|---|
| 用户字段 | 应用的 `API Key` 与 `Secret Key`；不是只填 `AppID`，也不能把百度通用云 AK/SK 名称直接套入此流程 |
| token 交换 | `POST https://aip.baidubce.com/oauth/2.0/token`；表单参数 `grant_type=client_credentials`、`client_id=<API Key>`、`client_secret=<Secret Key>` |
| token 响应 | 读取 `access_token`、`expires_in`。有效期按响应计算，不能只在 UI 写死“永久” |
| OCR 示例能力 | 通用文字识别高精度：`POST https://aip.baidubce.com/rest/2.0/ocr/v1/accurate_basic?access_token=…` |
| 图像请求 | `application/x-www-form-urlencoded`；字段 `image` 为纯 Base64，再进行表单编码；不能提交包含 `data:image/...` 的整段数据 URL |
| 文本响应 | `words_result[]` 中每项的 `words`，按识别顺序拼接；同时处理业务错误字段，HTTP 200 不必然代表成功 |
| 地区／模型 | 本接口没有聊天 `model`。接口能力选择影响计费和识别效果；不是更换 Prompt |

依据：[百度 OCR Postman 调用](https://cloud.baidu.com/doc/OCR/s/skruaza7j)、[获取 Access Token](https://cloud.baidu.com/doc/OCR/s/Ck3h7y2ia)、[高精度 OCR](https://cloud.baidu.com/doc/OCR/s/1k3h7y3db)。

**设计建议：**API Key、Secret Key 分成两个密码字段，保存在独立凭证项；短期 access token 在后端缓存，提前少量刷新，并对并发 token 刷新做合并。token 失败不得改走试用服务。日志必须抹除 URL 查询中的 `access_token`。官方示例中出现的关闭证书验证、输出 token 等做法不应复制到产品。额度显示只链接当前控制台／官方政策，本报告不承诺固定免费次数。[百度测试资源说明](https://cloud.baidu.com/doc/OCR/s/fk3h7xu7h)

### 4.2 腾讯：SecretId／SecretKey + TC3

| 项目 | 官方已确认 |
|---|---|
| 用户字段 | `SecretId`、`SecretKey`；使用临时凭证时另有 `Token`。长期密钥不能被命名成 Bearer API Key |
| 端点与请求 | `POST https://ocr.tencentcloudapi.com/`；`Content-Type: application/json` |
| 方法与版本 | `X-TC-Action: GeneralBasicOCR` 或 `GeneralAccurateOCR`；`X-TC-Version: 2018-11-19` |
| 地区 | 这两个接口的 `Region` 是可选参数，不能因为别的腾讯产品要求地区就错误设为必填 |
| 鉴权 | `TC3-HMAC-SHA256`；服务名 `ocr`；credential scope 为 `UTC日期/ocr/tc3_request`，**这里不含 region**；后端计算 Authorization，并设置 `X-TC-Timestamp` 等头；临时 Token 用 `X-TC-Token` |
| 图像与文字 | `ImageBase64` 或 `ImageUrl`；桌面截图使用前者；结果 `Response.TextDetections[].DetectedText`。Basic 可配置 `LanguageType`，例如 `auto`/`mix` |
| 大小边界 | Basic 文档限制 Base64 编码后的图片大小不超过 10M。不能只检查原始 PNG 大小 |

依据：[GeneralBasicOCR](https://cloud.tencent.com/document/api/866/33526)、[GeneralAccurateOCR](https://cloud.tencent.com/document/api/866/34937)、[OCR 专用签名规范](https://cloud.tencent.com/document/product/866/33519)。

Bob 教程采用子用户、编程访问和 OCR 权限流程。EchoLingo 应提供对应官方申请入口，建议仅赋所需 OCR 权限，不能让用户为了省步骤把主账号完整权限凭证贴进通用网关。免费额度按账号实际开通情况确认。[Bob：腾讯 OCR](https://bobtranslate.com/service/ocr/tencent.html)、[腾讯 OCR 免费额度](https://cloud.tencent.com/document/product/866/35945)

### 4.3 火山引擎：AK／SK + V4

火山 OCR 应填写 `Access Key ID`（AK）、`Secret Access Key`（SK），临时凭证另有安全 Token。官方 SDK 中通用 OCR 的接入点为 `visual.volcengineapi.com`，service=`cv`、region=`cn-north-1`，方法为 `POST /?Action=OCRNormal&Version=2020-08-26`；不是给聊天模型填一个 Bearer key。[火山官方 VisualService SDK](https://raw.githubusercontent.com/volcengine/volc-sdk-python/master/volcengine/visual/VisualService.py)

请求为表单，图像字段为 `image_base64`（纯 Base64）或 `image_url`；结果为 `data.line_texts[]`。签名采用 HMAC-SHA256 V4：scope 为 `日期/region/cv/request`，需要 UTC `X-Date`、规范化请求和分层 HMAC；临时凭证使用 `X-Security-Token`。这里的 scope 与腾讯 TC3 不同。[火山官方 SignerV4 SDK](https://raw.githubusercontent.com/volcengine/volc-sdk-python/master/volcengine/auth/SignerV4.py)

官方调用文档本次打开返回前端 JavaScript 壳，官方站点索引可见上述图像/响应字段及 Base64 后再 URL 编码的大小限制；SDK 补证了端点、服务、地区、Action/Version 和签名。**响应字段及编码后不超过 8MB 的限制在正式适配前仍应通过当前可渲染文档再次核对**，不能把抓取限制包装成真实请求验收。Bob 旧教程的“多语种 OCR”也不能直接等同于已验证的当前 Bob 内部 Action。[火山调用文档](https://docs.volcengine.com/docs/Largemodelofimagegeneration/Callingmethod?lang=zh)、[火山签名文档](https://docs.volcengine.com/docs/VideoLIVE/Signaturemethod?lang=en)、[Bob：火山 OCR](https://bobtranslate.com/service/ocr/volcengine.html)

### 4.4 有道：应用 ID／应用密钥 + v3 签名

用户填写“应用 ID”与“应用密钥”；请求字段 `appKey` 对应应用 ID，密钥参与签名而不是作为明文字段发送。端点为 `POST https://openapi.youdao.com/ocrapi`，请求是 `application/x-www-form-urlencoded`。通用 OCR 必填 `img`、`langType`、`detectType=10012`、`imageType=1`、`appKey`、`salt`、`curtime`、`docType=json`、`signType=v3`、`sign`；`langType` 可选 `auto`。`salt` 为随机值，`curtime` 为 UTC 秒。[有道通用 OCR API](https://ai.youdao.com/DOCSIRMA/html/ocr/api/tyocr/index.html)

签名为 `SHA256(appKey + input + salt + curtime + 应用密钥)`；当 Base64 图像字符串长度大于 20，`input` 为前 10 字符 + 长度十进制表示 + 后 10 字符，否则取完整字符串。成功 `errorCode="0"`，文本按 `Result.regions[].lines[].text` 拼接。图像 Base64 小于 5M、最长边小于 2048px，需按该接口限制单独准备图像，不能复用腾讯上限。[有道通用 OCR API](https://ai.youdao.com/DOCSIRMA/html/ocr/api/tyocr/index.html)

Bob 的教程要求创建应用并启用通用 OCR；IP 限制可能影响桌面客户端，但产品不应泛化为“关闭所有安全限制”。应先说明当前设备出口 IP、所用网络和厂商支持的限制方式。当前费用以官方页/控制台为准。[Bob：有道 OCR](https://bobtranslate.com/service/ocr/youdao.html)、[有道 OCR 计费](https://ai.youdao.com/DOCSIRMA/html/ocr/price/tyocr/index.html)

### 4.5 Google Cloud Vision：API Key 与 OAuth 分开

| 项目 | 官方已确认 |
|---|---|
| 前置开通 | Google Cloud 项目中启用 Vision API，配置相应结算及 API 限制；Bob 教程采用 API Key 路线 |
| 标准端点 | `POST https://vision.googleapis.com/v1/images:annotate` |
| 图像结构 | `requests[].image.content` 为 Base64；`requests[].features[].type` 可为 `TEXT_DETECTION` 或 `DOCUMENT_TEXT_DETECTION` |
| 常见整段文字 | `responses[0].fullTextAnnotation.text`；必须同时检查该响应项中的业务错误 |
| 鉴权选择 | Vision 接受 API Key 或 OAuth。API Key 可按 Google 通用规范放入 `x-goog-api-key`；OAuth 使用 `Authorization: Bearer <access_token>`。二者是不同配置模式 |
| 高级地区 | 区域端点形如 `https://REGION_ID-vision.googleapis.com/v1/projects/PROJECT_ID/locations/REGION_ID/images:annotate`；OCR 官方教程列出 `us`/`eu`。选择区域模式应同时填写 Project ID 与 location，不能只改 hostname |

依据：[Google OCR](https://docs.cloud.google.com/vision/docs/ocr)、[请求鉴权](https://docs.cloud.google.com/vision/docs/request)、[Google API Key 使用方式](https://docs.cloud.google.com/docs/authentication/api-keys-use)、[Vision 鉴权](https://docs.cloud.google.com/vision/docs/authentication)、[Bob：Google OCR](https://bobtranslate.com/service/ocr/google.html)。

**协议匹配推断，未做真实 API 验证：**现有 JSON 网关的“自定义静态 header + JSON 模板 + 字符串 JSON pointer”可表达 API Key 方式：header 为 `x-goog-api-key`、前缀为空、模板如下、路径 `/responses/0/fullTextAnnotation/text`。这不等于已实现 Google 原生预设；区域选择、开通诊断、业务错误、OAuth 刷新及凭证生命周期仍需专门处理。

```json
{
  "requests": [{
    "image": {"content": "{imageBase64}"},
    "features": [{"type": "DOCUMENT_TEXT_DETECTION"}]
  }]
}
```

## 5. EchoLingo 推荐的信息架构与字段 schema

### 5.1 三个能力页，两个配置层级

**文本翻译页：**服务列表显示供应商、模型/能力、启用状态、测试状态；提供添加、编辑、测试、删除和排序。多个启用服务分别出结果卡片；一家失败不应抹掉其他成功译文。后续再增加“按需调用”与默认替换服务。

**文字识别页：**顶部明确当前选择，本机 OCR 为初始值；其余为用户自己的百度、腾讯、Vision 等服务。保存多个配置不代表它们都要接收截图。切换到云服务时说明将把所选截图发往该供应商；日常快捷键不重复弹确认。静默 OCR 的“静默”表示不弹结果窗，不表示可以隐藏上传去向。

**语音朗读页：**首版若只有系统 TTS，就直接显示系统引擎及语音选择。云 TTS 上线后仍独立保存能力、声音与凭证，不能借用 OCR key。系统 TTS 是否联网取决于实际安装语音及平台实现，未验证前不要标“完全离线”。

**普通层：**供应商预设决定字段、鉴权、端点规则、图片限制、方法选项、错误映射；显示官方申请链接和账户控制台。**高级层：**OpenAI 兼容、自建 JSON 网关，明确这是协议配置，不保证任意厂商签名接口可直接套用。

### 5.2 建议 schema（设计稿，不是现有类型声明）

```text
ServiceDefinition
  id, category: translation | ocr | tts
  presetId, displayName, enabled, order
  transport: openai-chat | deepl | baidu-ocr | tencent-ocr | http-json | ...
  options: 由 preset 的字段 schema 校验
  credentialRef: 后端凭证引用；配置文件不含明文 secret
  validation: 未测试 | 测试中 | 成功 | 失败 | 配置已变更
  validationFingerprint: 非秘密配置版本 + 凭证版本号
  lastTestAt, safeErrorCode

FieldDefinition
  key, label, type: text | secret | select | url | multiline
  required, defaultValue, choices, helpUrl
  visibilityRule, validationRule

OcrSelection
  active: native | serviceId
  fallback: none（首版）
```

凭证 schema 应按供应商声明，例如百度 `{apiKey, secretKey}`、腾讯 `{secretId, secretKey, optionalToken}`、火山 `{accessKeyId, secretAccessKey, optionalSessionToken}`、有道 `{appKey, appSecret}`。这是后端存储结构，而不是让用户手写 JSON。任何导出都只含非秘密配置与“需重新填写凭证”标记，导入默认禁用云 OCR。

凭证引用需至少按能力、serviceId、协议类型隔离；把 OCR 类型从网关改为百度时不能把旧的 Bearer 字符串当作百度密钥。URL 编辑也应使已保存密钥状态失效，提示用户重新选择保留/替换，而不是悄悄将已有 secret 发送到新域名。删除服务同时提供删除对应凭证的明确行为。

### 5.3 原生适配器与 JSON 网关的分工

| 协议 | 当前通用 OCR 能否直接表达 | 后续所需能力 |
|---|---|---|
| OpenAI Vision | 已有请求结构与响应解析 | 模型视觉能力提示；兼容性说明；供应商预设与模型实际验收 |
| 自建 JSON OCR 网关 | 已有 JSON 模板、一个静态鉴权 header、字符串 JSON pointer | 网关自己负责上游 token/签名/数组拼接；客户端不运行任意脚本 |
| 百度 OCR | 仅靠现有 JSON 模板不能直接表达 | token 交换、双凭证、表单编码、业务错误、逐行结果；团队正在实现原生适配 |
| 腾讯 OCR | 仅靠静态 header 不能动态计算 TC3 | 双凭证、TC3、Action/Version、业务错误、逐行结果；团队正在实现原生适配 |
| 火山 OCR | 不能用一个 Bearer key 代替 V4 | AK/SK、地区/服务、V4、表单、业务错误、行结果；尚需原生适配或网关 |
| 有道 OCR | 不能通过字符串替换计算 v3 签名 | 应用双凭证、salt/时间、SHA256、表单、嵌套行结果；尚需原生适配或网关 |
| Google API Key OCR | JSON 网关在协议形状上可表达，尚未真实验证 | 原生预设、地区/Project、响应业务错误、鉴权方式明确；OAuth 是另一个工作量 |

JSON 模板只递归替换 JSON **字符串值**中的 `{imageBase64}` 或 `{imageDataUrl}`，不执行表达式、脚本或 shell；不能用模板中看似 `sign()` 的文字假装签名已完成。响应 JSON pointer 只选字符串，不代表支持 `words_result[*].words` 这种数组映射。通用接口必须把这些边界写进 UI 帮助。

## 6. 在线测试、启用与错误反馈

### 6.1 推荐状态转换

1. 新增预设，填写独立字段；本地检查空值、URL、安全 header、字段长度与方法枚举。
2. 保存为草稿／未测试；保存不会访问云端，也不会启用 OCR 上传。
3. 用户点击“测试连接”；显示固定示例输入及目标供应商域名，提示可能产生一次 API 费用。
4. 测试只请求这条服务，结果更新为成功或分类错误；不改变启用状态、排序、当前 OCR 引擎和历史记录。
5. 用户再启用翻译服务或选择 OCR 主引擎；正常任务才发送实际内容。
6. 修改影响请求的参数或凭证后回到“配置已变更”；网络暂时失败不会自动删除配置或换到另一家供应商。

安全且便宜的离线字段校验必须先做。远程 `GET /models` 一类接口并不能证明所选模型能翻译，也不能证明 Vision 能识图；不要把“账户可访问”与“所选能力通过”混为一谈。测试用内置小图，不能自动截取用户当前屏幕。

### 6.2 诊断与配额

错误应尽可能分类为：缺少字段、服务未开通、鉴权失败、权限不足、地区/端点不匹配、余额/额度不足、速率限制、图片过大、模型不支持图像、系统时间偏差、超时、业务错误、响应结构不符、空识别结果。对 UI 只返回经过映射的短错误与可选请求 ID，不能回显整个上游响应、Authorization、URL token、截图 Base64 或密钥。

DeepL 的 `GET /v2/usage` 可以提供当前周期用量与限额，API Free/Pro 返回形状不同；未来可以做明确的“刷新配额”按钮，但本次未实现。它查询的是当前 key/account 的厂商数据，不应与本地字符计数相加。[DeepL：usage 与限额](https://developers.deepl.com/api-reference/usage-and-quota/check-usage-and-limits)

多翻译并发时，任务应绑定一个配置快照与请求 ID，结果按保存顺序呈现；新任务或用户取消后，旧响应不得覆盖新内容。OCR 仅取当次所选主引擎，无自动付费重试；失败时保留重试入口和本地识别选项。响应体、图像与超时都须有上限，并按每家**编码后**的限制检查。

## 7. 对照仓库的改进顺序与验收

以下依据 2026-10-24 写作时的源码快照。仓库正在并行修改，最终“完成”状态应以对应提交、构建、自动测试和实机记录更新，不能用本文替代发布验收。

### P0：发布前必须保持真实、安全的能力边界

| 项目 | 本次观察／风险 | 发布要求 |
|---|---|---|
| 默认本机 OCR | Settings 默认未选择云 OCR；已有明确云选择入口 | 全新安装无 key 时本机 OCR 可用；禁止隐式云兜底；网络抓取确认本机 OCR 无供应商上传 |
| 原生百度／腾讯 | 原生模块、独立双字段已实现，本地协议及签名测试通过 | 仍未进行实际用户账户验收；腾讯官方签名向量、百度 token/表单、图片上限和业务错误均有覆盖 |
| 凭证隔离 | 后端已有按协议隔离 OCR 凭证标识的代码 | 切换类型/端点不会泄漏旧 key；配置导出、历史、日志不含 secret；失败也不回显上游正文 |
| 验证与启用 | 已有单服务测试命令与启停/当前 OCR 配置 | 测试不修改启用或主引擎、不捕获真实屏幕；说明发送示例及可能计费；错误提示不误导 |
| 供应商预设真实性 | 文本翻译现有核心 transport 为 OpenAI/DeepL/LibreTranslate；前端预设正在扩展 | 兼容模型预设可复用 transport；阿里机器翻译、火山、有道不能只改名称冒充原生协议 |
| 本地／云内容去向 | “静默 OCR”可能让用户误以为绝不联网 | 设置页持续明确当前引擎；选云后上传目标可见，默认仍为本机 |

### P1：使配置可靠且容易理解

- 以 schema 渲染独立字段，百度与腾讯优先；OpenAI、DeepSeek、智谱、硅基流动、百炼作为不同预设，共用兼容传输，保留准确 Base URL 和模型手填。
- 百度按 `expires_in` 缓存并合并刷新；腾讯采用确定的签名向量，覆盖 UTC 跨日、中文、特殊字符、正文序列化和临时 Token；不记录签名材料。
- 添加火山、有道原生适配前分别验证 V4/v3，不建立一个“万能云 OCR Key”。Google API Key 可先做受限预设；OAuth 支持另立任务。
- 翻译排序与多结果、单 OCR 当前选择保持独立；增加“未测试／配置已变更”状态，不用 `hasKey` 冒充“连接成功”。
- 供应商限额、语言/模型不支持、HTTP 200 业务错误用可理解的错误映射；quota 为未知时显示未知。
- 按每家编码限制准备图像，必要时明确缩放策略；文本 OCR 与带坐标 OCR 结构分开，为以后原图翻译保留框、语言和方向，而非假定纯字符串足以回填。

### 最小可验收场景

| 场景 | 预期 |
|---|---|
| 新装无凭证，断网截图 OCR | 使用本地引擎；若语言包缺失准确提示；不尝试云请求 |
| 保存百度双字段但不测试、不选择 | 不联网、不上传；当前仍为本机 |
| 显式测试百度 | 只发内置测试图；token 获取失败有分类错误；不会切换主引擎或写入用户历史 |
| 并发两次百度识别，token 已过期 | token 刷新合并；请求使用有效 token；无无限刷新/重试循环 |
| 腾讯 SecretId/SecretKey 填反、时间明显偏差 | 不回显凭证；分别提示鉴权/签名或时间相关原因，不简单吞成“无文字” |
| 云 OCR 返回 HTTP 200 + 厂商错误码 | 作为失败显示，不把错误消息当成识别结果 |
| 修改端点或类型后测试 | 不把旧凭证默默发往新域名或当成另一协议；成功状态失效 |
| 启用三家翻译，其中一家失败 | 成功译文继续显示、顺序稳定；本次费用提示与服务数相符 |
| 测试后禁用服务／切回本机 OCR | 后续快捷键只使用当前有效配置；无后台重复上传 |
| Base64、URL 编码后越过厂商限制 | 本地明确拒绝或按已说明策略处理；不依赖厂商 413 才发现 |
| 导出／导入配置 | 无 secret/token；云 OCR 导入后不自动变成当前引擎 |

## 8. 资料使用与未决事项

上述链接均为本次实际打开的官方来源；火山现文档的 JavaScript 渲染限制已单独标出，另以官方 SDK 补证。未复用 Bob 源代码、图标、插件或其内部服务凭证。Bob 的合作免费服务、旧价格和旧控制台截图只用于理解产品设计，不作为 EchoLingo 当前权益承诺。

尚需后续工作：供应商真实账户的显式验收、Windows 原生 OCR 语言包与多屏实测、macOS 系统 OCR 权限实测、原生火山/有道协议接入、Google OAuth 生命周期、TTS 独立配置。真实账户测试应由用户自行填写自己的凭证，研究与开发过程中不读取别的软件私有存储来补齐字段。
