# 免费配置指南

默认仍然是本机翻译和本机 OCR：不上传文字，也不上传截图。下面的云端服务只在你自己开通并启用之后才会使用。

额度核对于 **2026-10**。服务商会改免费层、地区和计费方式。这里不是永久免费的承诺，以各家控制台当时的说明为准。有的服务在免费额度用完后会自动转为按量计费。开通后请到控制台确认是否有「用完即停」等控制；并非每个平台都支持，应用不会替你阻止超额计费。

应用里的独立服务列表可以按中国大陆或海外查看额度、打开申请页、粘贴你自己的密钥、测试连接并启用。密钥只写入操作系统凭据库，不要发到 Issue、聊天或截图里。

## 为什么默认是本机

本机引擎没有注册和欠费。长文、术语和小字截图往往不如云端。你可以随时加一个云端服务，也可以继续保留本机作为兜底。

## 独立选择，不再绑定组合

设置里的「有免费额度的服务」分为 **翻译服务** 和 **OCR 服务** 两份列表。地区只用于整理可选平台，不保证直连或账号资格。你可以只添加翻译、只添加 OCR，或选择不同平台自由搭配；配置其中一项不会顺带更换另一项。成功测试后才启用你选中的服务。

以下额度于 **2026-10-30** 核对官方公开资料。列表只包含已支持的协议，不是永久免费的承诺。

### 翻译服务

| 平台 | 免费量与周期 | 必要条件 / 注意事项 | 官方来源 |
| --- | --- | --- | --- |
| 硅基流动 Hunyuan-MT-7B | 指定模型输入/输出单价 0；无固定月度 Token 数 | 中国站指定模型；仍受限流，其他模型收费 | [价格页](https://www.siliconflow.cn/pricing) |
| 百度通用翻译 | 标准 5 万字符/月；高级 100 万字符/月 | 高级版需个人认证并开通版本，额度不叠加 | [额度与开通](https://fanyi-api.baidu.com/access/0/1) |
| 智谱 GLM-4-Flash-250414 | 指定免费模型；无固定月度 Token 数 | 并发/速率限制，不代表全平台免费 | [免费模型](https://docs.bigmodel.cn/cn/guide/models/free/glm-4-flash-250414) |
| 火山引擎机器翻译 | 文本前 200 万字符/月 | 需实名、联系销售签约开通；默认后付费 | [计费](https://docs.volcengine.com/docs/machine-translation/product-billing) |
| 阿里云机器翻译通用版 | 100 万字符/月 | 主账号和子账号共享，月初刷新不结转；超量自动后付费 | [计费](https://help.aliyun.com/zh/machine-translation/product-overview/billing-overview) |
| Azure Translator F0 | 200 万字符/月 | 创建 F0 资源；标准翻译与自定义训练共用 | [F0 价格](https://azure.microsoft.com/en-us/pricing/details/translator/) |
| DeepL API Developer | 新用户累计 100 万字符，一次性、不按月重置 | 旧 Free 的每月 50 万仅已有账户，不能新开 | [套餐](https://support.deepl.com/hc/en-us/articles/360021200939-DeepL-API-plans) |
| 百炼通义千问 · 新人试用 | 北京符合条件模型通常各 100 万 Token，一次性、90 天 | 输入输出共享，具体模型以控制台为准；可启用免费额度用完即停 | [新人额度](https://help.aliyun.com/zh/model-studio/new-free-quota/) |
| 有道智云 · 新人试用 | 注册 10 元 + 实名 40 元，一次性 | 与有道 OCR 共用体验金，不是月额度；有效期以账户为准 | [价格中心](https://ai.youdao.com/new/newuser-promotion.s) |

### OCR 服务

| 平台 | 免费量与周期 | 必要条件 / 注意事项 | 官方来源 |
| --- | --- | --- | --- |
| 百度 OCR | 标准/高精度对应接口：个人各 1000 次/月；企业各 2000 次/月 | 实名并进入控制台后按规则自动发放；翻译 APP ID 不适用 | [测试资源](https://ai.baidu.com/ai-doc/OCR/fk3h7xu7h) |
| 腾讯云 OCR | 通用/高精度对应资源包各 1000 次/月 | 中国站实名开通；按共享规则扣减，不结转，长期不用可能暂停发放 | [免费额度](https://cloud.tencent.com/document/product/866/35945) |
| 智谱 GLM-4V-Flash | 指定视觉模型免费，无固定月次数 | 图片上传到智谱，受限流 | [模型](https://docs.bigmodel.cn/cn/guide/models/free/glm-4v-flash) |
| Google Cloud Vision | Text/Document 每功能前 1000 units/月 | 需结算项目；逐图/逐页计量，不等于 HTTP 请求数 | [价格](https://cloud.google.com/vision/pricing) |
| Azure AI Vision F0 | 5000 transactions/月；20 次/分钟 | 创建 F0，地区可能不可用 | [价格](https://azure.microsoft.com/en-us/pricing/details/computer-vision/) |
| OCR.space Engine 1/2 | 25000 次/月；另限 500 次/日/IP、1 MB/文件 | 使用自己的 Key；两种周期限制同时适用 | [API](https://ocr.space/ocrapi) |
| 有道智云 · 新人试用 | 注册 10 元 + 实名 40 元，一次性 | 与有道翻译共用同一体验金，不能再算一份 | [价格中心](https://ai.youdao.com/new/newuser-promotion.s) |

本机翻译与本机 OCR 仍是默认，不需云账号、没有按次云端额度。没有固定免费量或未核实的服务仍可从完整设置手动添加，不放入本推荐列表。

## 申请与配置

### 硅基流动

1. 打开[硅基流动控制台](https://cloud.siliconflow.cn/)并创建 API Key。
2. 在 EchoLingo 添加硅基流动，模型填 `tencent/Hunyuan-MT-7B`。
3. 点「测试连接」。测试会发送短句 Hello。

### 百度翻译

1. 打开[百度翻译管理控制台](https://fanyi-api.baidu.com/manage/developer)，开通通用文本翻译。
2. 填写 APP ID 和密钥。不要填百度智能云 OCR 的 Key。
3. 个人认证并开通高级版后，额度通常高于标准版。以控制台为准。

### 百度 OCR

1. 打开[百度 OCR 控制台](https://console.bce.baidu.com/ai/#/ai/ocr/overview/index)，按官方规则获得通用文字识别测试资源。
2. 填写 API Key 和 Secret Key。
3. 在「识别方式」里选中它。之后的截图会上传到百度。

### 腾讯云 OCR

1. 开通文字识别，在[访问管理](https://console.cloud.tencent.com/cam/capi)创建 SecretId / SecretKey。
2. 地域可先用 `ap-guangzhou`，与控制台资源一致即可。
3. 看一眼计费设置，避免免费包用完后继续扣费。

### 智谱

1. 在[智谱开放平台](https://open.bigmodel.cn/)创建 API Key。
2. 翻译模型用 `glm-4-flash-250414`，识图用 `glm-4v-flash`，地址都是 `https://open.bigmodel.cn/api/paas/v4`。
3. 识图会上传选区图片。

### 火山引擎机器翻译

1. 阅读[计费说明](https://docs.volcengine.com/docs/machine-translation/product-billing)并开通机器翻译。
2. 在[AccessKey 管理](https://console.volcengine.com/iam/keymanage/)创建密钥。
3. 在设置里添加「火山引擎 · 机器翻译」，填写 AccessKey ID 和 Secret Access Key，然后测试连接。

### 阿里云机器翻译

1. 阅读[计费说明](https://help.aliyun.com/zh/machine-translation/product-overview/billing-overview)。这不是百炼。
2. 在[AccessKey 管理](https://ram.console.aliyun.com/manage/ak)创建 RAM 用户的 AccessKey。
3. 添加「阿里云 · 机器翻译」并测试。免费额度用完后会自动进入后付费，使用前确认计费风险。

### Azure Translator

创建 Translator 资源时选择 F0，复制密钥。区域或多服务资源还要填写地域。使用应用里的全球端点。

### Google Vision

在项目里启用 Vision API，创建只允许 Vision 的 API Key。图片会上传到 Google。

### DeepL

新用户开通 API Developer，端点用 `https://api-free.deepl.com/v2`。不要把旧的每月 Free 当成还能新开的套餐。

### Azure AI Vision Read

创建 F0 资源，把 `https://你的资源名.cognitiveservices.azure.com` 和密钥填进 OCR 服务。应用只接受这个域名下你自己的资源，不会代你保存一份公共密钥。

### Gemini（仅手动配置）

Gemini 不列入推荐免费服务列表。手动添加 OpenAI 兼容服务前，请核对 Google 当前的[使用资格和数据条款](https://ai.google.dev/gemini-api/terms)：条款限制可用地区、专业或商业用途及使用年龄；向欧洲经济区、瑞士或英国用户提供 API 客户端时，要求使用 Paid Services。账号和用途是否符合要求，应以 Google 当前条款为准，不由本应用保证。

适用未付费服务数据条款时，提交的内容及回复可能用于改进 Google 产品，并可能经过人工审阅；不要提交敏感、机密或个人信息。付费服务及部分地区的数据条款不同，请按自己的情况核对上述原文。

根据自己账号实际可用的模型，查阅[模型生命周期](https://ai.google.dev/gemini-api/docs/deprecations)及[价格页](https://ai.google.dev/gemini-api/docs/pricing)后填写模型名称；本指南不预填模型，也不承诺免费访问。

### OCR.space

在 [OCR.space API](https://ocr.space/ocrapi) 注册并复制你自己的 Key。不要使用页面上的公共示例密钥 `helloworld`，应用会拒绝它。

## 隐私

本机翻译和 OCR 在你的电脑上完成。启用云端翻译后，你提交的原文会发给该翻译服务。启用云端 OCR 后，选区图片会发给该 OCR 服务；如果接着用云端翻译，识别出的文字还会再发一次。不要翻译或识别你不想交给第三方的内容。

## 密钥

密钥不写在设置文件里，也不要贴到本仓库的 Issue。测试连接只用很短的示例，不会把你的文档发出去，但云端仍然会收到这个测试文本或测试图片。
