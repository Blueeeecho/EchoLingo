# Free setup guide

The default remains on-device translation and on-device OCR. Nothing is uploaded until you add and enable a cloud service yourself.

Quotas below were **checked in 2026-10**. Vendors change free tiers, regions, and billing. This is not a promise that anything stays free. After a free tier, some providers start charging automatically. In that provider's console, turn off post-paid billing or enable stop-when-exhausted.

Settings includes recommended combinations for mainland China and for overseas use. The wizard opens the signup page, accepts your own key, tests the connection, and can set that service as current. Keys go to the operating system credential store. Do not post them in issues, chat, or screenshots.

## Why local is the default

Local engines need no account and cannot run up a bill. Long text, terminology, and small screenshot text are often better in the cloud. You can add a cloud service and still keep the local engine.

## Mainland China

| Combination | Translation | OCR | What the public pages said in 2026-10 |
| --- | --- | --- | --- |
| First choice | SiliconFlow `tencent/Hunyuan-MT-7B` | Baidu OCR standard | That model's listed input/output price is 0, with rate limits; Baidu OCR personal verification is about 1,000 calls/month |
| Alternate | Baidu Translate advanced | Tencent Cloud OCR | About 1 million characters/month after personal verification; OCR about 1,000 calls/month, then possibly paid |
| One account | Zhipu GLM-4-Flash | Zhipu GLM-4V-Flash | Listed as free models at that time, with rate limits. Not every Zhipu model is free |

Baidu Translate APP ID / secret and Baidu OCR API key / secret are different. The wizard asks for them separately.

You can also add Volcengine machine translation (about the first 2 million characters/month) or Aliyun Machine Translation general edition (about 1 million characters/month). Aliyun Machine Translation is not the Bailian / Qwen API. Do not add Tencent text translation; its free packs are being discontinued.

### SiliconFlow

1. Create an API key in the [SiliconFlow console](https://cloud.siliconflow.cn/).
2. Add SiliconFlow in EchoLingo with model `tencent/Hunyuan-MT-7B`.
3. Use Test connection. The test sends the short text Hello.

### Baidu Translate

1. Open the [Baidu Translate console](https://fanyi-api.baidu.com/manage/developer) and enable general text translation.
2. Enter the APP ID and secret. Do not paste a Baidu OCR key.
3. Personal verification plus the advanced plan usually has a larger quota. The console wins if they differ.

### Baidu OCR

1. Open the [Baidu OCR console](https://console.bce.baidu.com/ai/#/ai/ocr/overview/index) and claim the general-text trial quota.
2. Enter the API key and secret key.
3. Select it as the recognizer. Later screenshots are uploaded to Baidu.

### Tencent Cloud OCR

1. Enable OCR and create a SecretId / SecretKey in [access management](https://console.cloud.tencent.com/cam/capi).
2. `ap-guangzhou` is a reasonable first region if it matches the console.
3. Check billing settings so a used-up free pack does not keep charging.

### Zhipu

1. Create an API key on the [BigModel console](https://open.bigmodel.cn/).
2. Use `glm-4-flash` for translation and `glm-4v-flash` for images, both at `https://open.bigmodel.cn/api/paas/v4`.
3. Image recognition uploads the selected picture.

### Volcengine machine translation

1. Read the [billing page](https://docs.volcengine.com/docs/machine-translation/product-billing) and enable machine translation.
2. Create a key in [AccessKey management](https://console.volcengine.com/iam/keymanage/).
3. Add Volcengine machine translation in Settings and test the connection.

### Aliyun Machine Translation

1. Read the [billing page](https://help.aliyun.com/zh/machine-translation/product-overview/billing-overview). This is not Bailian.
2. Create an AccessKey in [RAM](https://ram.console.aliyun.com/manage/ak).
3. Add Aliyun Machine Translation and test it. Turn off post-paid billing or enable stop-when-exhausted.

## Overseas

| Combination | Translation | OCR | What the public pages said in 2026-10 |
| --- | --- | --- | --- |
| First choice | Azure Translator F0 | Google Cloud Vision | F0 about 2 million characters/month; about 1,000 units/month per text feature |
| Alternate | DeepL API Developer | Azure AI Vision F0 | About 1 million characters total for new Developer accounts, not a monthly reset; Vision F0 about 5,000 calls/month, unavailable in some regions |

DeepL, Google, and Gemini are often unreachable directly from mainland China, so they are not the mainland recommendations.

### Azure Translator

Create a Translator resource on the F0 tier and copy the key. Regional or multi-service resources also need the region. The app uses the global endpoint.

### Google Vision

Enable the Vision API and create an API key restricted to Vision. Images are uploaded to Google.

### DeepL

Open API Developer and use `https://api-free.deepl.com/v2`. The older monthly Free plan is not available to new accounts.

### Azure AI Vision Read

Create an F0 resource and enter `https://your-resource.cognitiveservices.azure.com` plus the key. The app only accepts your own host under that suffix. It does not ship a shared key.

### Gemini (manual configuration only)

Gemini is not a recommended free combination. Check Google's current [eligibility and data-use terms](https://ai.google.dev/gemini-api/terms) before configuring an OpenAI-compatible service manually: the terms limit use to supported regions and professional/business purposes, include age restrictions, and require Paid Services when making API clients available to users in the EEA, Switzerland or UK. Whether your account and use qualify depends on Google's current terms, not on this app.

Where the unpaid-service data terms apply, submitted content and responses may be used to improve Google's products and reviewed by people; do not send sensitive, confidential or personal data. Paid-service and some regional data terms differ. Review the linked terms for your situation.

Select a currently available model in your own account using the [model lifecycle list](https://ai.google.dev/gemini-api/docs/deprecations) and [pricing page](https://ai.google.dev/gemini-api/docs/pricing); this guide does not preselect a model or promise free access.

### OCR.space

Register at the [OCR.space API](https://ocr.space/ocrapi) and copy your own key. Do not use the public sample key `helloworld`. The app rejects it.

## Privacy

On-device translation and OCR stay on your computer. After you enable a cloud translator, the source text you submit is sent to that translator. After you enable cloud OCR, the selected image is sent to that OCR provider. If a cloud translator then runs, the recognized text is sent as well. Do not translate or recognize anything you do not want a third party to receive.

## Keys

Keys are not written into the settings file. Do not paste them into an issue. Test connection sends only a short sample, but that sample does go to the cloud service.
