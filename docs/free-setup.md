# Free service setup

Local translation and local OCR remain the defaults. Cloud services are optional and independent: configuring translation does not configure OCR, and configuring OCR does not change translation. Keys stay in the OS credential store.

## Choose translation and OCR independently

Settings now shows two lists, **Translation services** and **OCR services**, with region grouping. Each row shows the allowance, reset or expiry rules, eligibility, official source and verification date. Choose any supported service in either role, or keep one role local. The generic entry opens the lists; it never silently chooses a vendor. A successful test enables only the selected service.

Official public allowances checked **2026-10-30**. They may change. Region grouping does not guarantee connectivity or account eligibility. Overages may be billed; not every provider offers a stop-after-free switch.

### Translation

- **SiliconFlow Hunyuan-MT-7B:** named model input/output price 0, no fixed monthly Token allowance; rate/concurrency limits. [Pricing](https://www.siliconflow.cn/pricing)
- **Baidu:** Standard 50,000 characters/month; Advanced 1,000,000/month after personal verification and version activation. Tiers do not stack. [Official allowance](https://fanyi-api.baidu.com/access/0/1)
- **Zhipu GLM-4-Flash-250414:** named free model, no fixed monthly Token allowance, rate limits apply. [Model](https://docs.bigmodel.cn/cn/guide/models/free/glm-4-flash-250414)
- **Volcengine machine translation:** first 2,000,000 characters/month; activate through the vendor's sales/contract process, default post-paid billing. [Billing](https://docs.volcengine.com/docs/machine-translation/product-billing)
- **Alibaba Cloud machine translation:** General edition 1,000,000 characters/month, subaccounts share the main quota, resets monthly without rollover; paid usage follows exhaustion. Not Bailian. [Billing](https://help.aliyun.com/zh/machine-translation/product-overview/billing-overview)
- **Azure Translator F0:** 2,000,000 characters/month, shared by standard translation and custom training; create an F0 resource. [Pricing](https://azure.microsoft.com/en-us/pricing/details/translator/)
- **DeepL API Developer:** new users receive 1,000,000 characters total, not monthly. Legacy Free 500,000/month is for existing accounts only. [Plans](https://support.deepl.com/hc/en-us/articles/360021200939-DeepL-API-plans)
- **Qwen introductory trial:** eligible Beijing models typically 1,000,000 Tokens/model, once, 90 days; input/output share quota. Enable the vendor's stop-when-exhausted control if appropriate. [Quota](https://help.aliyun.com/zh/model-studio/new-free-quota/)
- **Youdao introductory credit:** CNY 10 registration plus CNY 40 identity verification, once; account expiry/eligibility apply. Shared with OCR. [Price center](https://ai.youdao.com/new/newuser-promotion.s)

### OCR

- **Baidu:** supported Standard/Accurate interfaces each 1,000 calls/month personal or 2,000 enterprise; verified users enter the console to receive resources under vendor rules. Different credentials from Baidu Translation. [Quota](https://ai.baidu.com/ai-doc/OCR/fk3h7xu7h)
- **Tencent Cloud:** 1,000 calls/month in each corresponding Basic/Accurate resource pack, subject to shared-pack rules; China account, verification and activation. No rollover; long inactivity can pause issuance. [Quota](https://cloud.tencent.com/document/product/866/35945)
- **Zhipu GLM-4V-Flash:** named free vision model, no fixed monthly call allowance; images go to BigModel, rate limits apply. [Model](https://docs.bigmodel.cn/cn/guide/models/free/glm-4v-flash)
- **Google Cloud Vision:** first 1,000 units/month per Text/Document Text Detection feature; billing-enabled project; per-image/page units, not HTTP calls. [Pricing](https://cloud.google.com/vision/pricing)
- **Azure AI Vision F0:** 5,000 transactions/month and 20/minute, region availability varies. Use your own resource endpoint. [Pricing](https://azure.microsoft.com/en-us/pricing/details/computer-vision/)
- **OCR.space Engine 1/2:** 25,000 requests/month, additionally 500/day/IP and 1 MB/file. Use your own key, not the public sample key. [API](https://ocr.space/ocrapi)
- **Youdao introductory credit:** same one-time CNY 10 + CNY 40 account pool as translation, not an additional allowance. [Price center](https://ai.youdao.com/new/newuser-promotion.s)

Local engines need no cloud quota or account. Providers without a confirmed free allowance remain available through the complete manual settings rather than this list. No new adapters are implied.

## Privacy and billing

A translation connection test sends a short sample text; an OCR test sends a sample image. Later cloud translation uploads source text, and cloud OCR uploads the selected image. Only enable a provider after reviewing its terms. The app stores keys in the OS credential store, not the settings file. Never share keys in issues or screenshots.

Gemini remains manual-only. Before adding an OpenAI-compatible endpoint, review Google's [eligibility and data terms](https://ai.google.dev/gemini-api/terms), [model lifecycle](https://ai.google.dev/gemini-api/docs/deprecations), and [pricing](https://ai.google.dev/gemini-api/docs/pricing). Do not assume free API eligibility or submit sensitive information under unpaid-service data terms.
