# 免费配置指南

默认仍然是本机翻译和本机 OCR：不上传文字，也不上传截图。下面的云端组合只在你自己开通并启用之后才会使用。

额度核对于 **2026-10**。服务商会改免费层、地区和计费方式。这里不是永久免费的承诺，以各家控制台当时的说明为准。有的服务在免费额度用完后会自动转为按量计费。开通后请到控制台关闭后付费，或打开「用完即停」。

应用里的「推荐免费组合」可以按中国大陆或海外打开申请页、粘贴你自己的密钥、测试连接并设为当前。密钥只写入操作系统凭据库，不要发到 Issue、聊天或截图里。

## 为什么默认是本机

本机引擎没有注册和欠费。长文、术语和小字截图往往不如云端。你可以随时加一个云端服务，也可以继续保留本机作为兜底。

## 中国大陆

| 组合 | 翻译 | OCR | 2026-10 看到的额度 |
| --- | --- | --- | --- |
| 首选 | 硅基流动 `tencent/Hunyuan-MT-7B` | 百度 OCR 标准版 | 该模型价格页输入/输出单价为 0，仍有限流；百度 OCR 个人认证约 1000 次/月 |
| 备选 | 百度翻译高级版 | 腾讯云 OCR | 个人认证后约 100 万字符/月；OCR 约 1000 次/月，用完可能按量 |
| 同一账号 | 智谱 GLM-4-Flash | 智谱 GLM-4V-Flash | 模型页当时标为免费，有速率限制，不是所有智谱模型都免费 |

百度翻译的 APP ID / 密钥和百度 OCR 的 API Key / Secret Key 不是同一套，向导里会分开填写。

也可以在「添加服务」里单独配置火山引擎机器翻译（文本每月前约 200 万字符）或阿里云机器翻译通用版（约 100 万字符/月）。阿里云机器翻译不是百炼通义千问。不要新接腾讯云文本翻译，免费资源包已在停止发放。

### 硅基流动

1. 打开[硅基流动控制台](https://cloud.siliconflow.cn/)并创建 API Key。
2. 在 EchoLingo 添加硅基流动，模型填 `tencent/Hunyuan-MT-7B`。
3. 点「测试连接」。测试会发送短句 Hello。

### 百度翻译

1. 打开[百度翻译管理控制台](https://fanyi-api.baidu.com/manage/developer)，开通通用文本翻译。
2. 填写 APP ID 和密钥。不要填百度智能云 OCR 的 Key。
3. 个人认证并开通高级版后，额度通常高于标准版。以控制台为准。

### 百度 OCR

1. 打开[百度 OCR 控制台](https://console.bce.baidu.com/ai/#/ai/ocr/overview/index)，领取通用文字识别测试资源。
2. 填写 API Key 和 Secret Key。
3. 在「识别方式」里选中它。之后的截图会上传到百度。

### 腾讯云 OCR

1. 开通文字识别，在[访问管理](https://console.cloud.tencent.com/cam/capi)创建 SecretId / SecretKey。
2. 地域可先用 `ap-guangzhou`，与控制台资源一致即可。
3. 看一眼计费设置，避免免费包用完后继续扣费。

### 智谱

1. 在[智谱开放平台](https://open.bigmodel.cn/)创建 API Key。
2. 翻译模型用 `glm-4-flash`，识图用 `glm-4v-flash`，地址都是 `https://open.bigmodel.cn/api/paas/v4`。
3. 识图会上传选区图片。

### 火山引擎机器翻译

1. 阅读[计费说明](https://docs.volcengine.com/docs/machine-translation/product-billing)并开通机器翻译。
2. 在[AccessKey 管理](https://console.volcengine.com/iam/keymanage/)创建密钥。
3. 在设置里添加「火山引擎 · 机器翻译」，填写 AccessKey ID 和 Secret Access Key，然后测试连接。

### 阿里云机器翻译

1. 阅读[计费说明](https://help.aliyun.com/zh/machine-translation/product-overview/billing-overview)。这不是百炼。
2. 在[AccessKey 管理](https://ram.console.aliyun.com/manage/ak)创建 RAM 用户的 AccessKey。
3. 添加「阿里云 · 机器翻译」并测试。建议关闭后付费或打开用完即停。

## 海外

| 组合 | 翻译 | OCR | 2026-10 看到的额度 |
| --- | --- | --- | --- |
| 首选 | Azure Translator F0 | Google Cloud Vision | F0 约 200 万字符/月；每个文字功能约 1000 units/月 |
| 备选 | DeepL API Developer | Azure AI Vision F0 | 新客累计约 100 万字符，用完不按月恢复；Vision F0 约 5000 次/月，部分区域没有 |
| 低门槛 | Gemini 免费层 | OCR.space | 以价格页标为 Free of charge 的模型为准；OCR.space Engine 1/2 约 25000 次/月，另有每日 IP 限制 |

DeepL、Google、Gemini 在中国大陆经常无法直连，大陆组合里不把它们当首选。

### Azure Translator

创建 Translator 资源时选择 F0，复制密钥。区域或多服务资源还要填写地域。使用应用里的全球端点。

### Google Vision

在项目里启用 Vision API，创建只允许 Vision 的 API Key。图片会上传到 Google。

### DeepL

新用户开通 API Developer，端点用 `https://api-free.deepl.com/v2`。不要把旧的每月 Free 当成还能新开的套餐。

### Azure AI Vision Read

创建 F0 资源，把 `https://你的资源名.cognitiveservices.azure.com` 和密钥填进 OCR 服务。应用只接受这个域名下你自己的资源，不会代你保存一份公共密钥。

### Gemini

在 [Google AI Studio](https://aistudio.google.com/apikey) 创建 Key。向导预填 OpenAI 兼容地址和 `gemini-2.0-flash`。如果价格页上的免费模型名称不同，在设置里改模型后再测试。

### OCR.space

在 [OCR.space API](https://ocr.space/ocrapi) 注册并复制你自己的 Key。不要使用页面上的公共示例密钥 `helloworld`，应用会拒绝它。

## 隐私

本机翻译和 OCR 在你的电脑上完成。启用云端翻译后，你提交的原文会发给该翻译服务。启用云端 OCR 后，选区图片会发给该 OCR 服务；如果接着用云端翻译，识别出的文字还会再发一次。不要翻译或识别你不想交给第三方的内容。

## 密钥

密钥不写在设置文件里，也不要贴到本仓库的 Issue。测试连接只用很短的示例，不会把你的文档发出去，但云端仍然会收到这个测试文本或测试图片。
