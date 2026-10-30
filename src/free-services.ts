import { EXTRA_SERVICE_LINKS, TRANSLATION_QUOTAS, OCR_QUOTAS, type ServiceQuota } from './service-quotas';

export type FreeRegion = 'cn' | 'overseas';
export type FreeCredential = 'apiKey' | 'appPair' | 'ocrPair' | 'tencentOcr' | 'microsoft' | 'azureVision' | 'youdaoPair';
export interface FreePiece {
  id: string;
  role: 'translation' | 'ocr';
  regionGroup: FreeRegion;
  name: string;
  nameEn: string;
  kind: string;
  baseUrl: string;
  model: string;
  editableModel?: boolean;
  // Enrollment date in China (UTC+8); only recommendations expire, never saved services.
  recommendUntil?: string;
  region?: string;
  prompt?: string;
  signupUrl: string;
  credential: FreeCredential;
  allowance: ServiceQuota;
  quotaEn: string;
  conditionsEn: string;
}

// Each entry is independent. No implicit translation/OCR pairing, shared key,
// or second step; adding a service never changes the other role.
const glmVisionQuota: ServiceQuota = {
  badge: '指定模型免费', summary: 'GLM-4V-Flash 免费；无统一月度次数承诺。',
  details: ['图片上传到智谱；受速率限制，其他模型按各自价格计费。'],
  allowances: [], links: [['官方免费视觉模型', EXTRA_SERVICE_LINKS.glmVision]], checkedOn: '2026-10-30',
};

export const FREE_SERVICES: readonly FreePiece[] = [
  { role: 'translation', name: '硅基流动', kind: 'openai', baseUrl: 'https://api.siliconflow.cn/v1', model: 'tencent/Hunyuan-MT-7B', signupUrl: 'https://cloud.siliconflow.cn/', credential: 'apiKey', id: 'siliconflow', nameEn: 'SiliconFlow', regionGroup: 'cn', allowance: TRANSLATION_QUOTAS.siliconflow, quotaEn: 'Named Hunyuan-MT-7B model: input/output price 0; no fixed monthly Token allowance.', conditionsEn: 'Other models may charge; rate/concurrency limits apply.' },
  { role: 'ocr', name: '百度 OCR', kind: 'baidu', baseUrl: 'https://aip.baidubce.com', model: 'general_basic', signupUrl: 'https://console.bce.baidu.com/ai/#/ai/ocr/overview/index', credential: 'ocrPair', id: 'baidu-ocr', nameEn: 'Baidu OCR', regionGroup: 'cn', allowance: OCR_QUOTAS.baidu, quotaEn: 'Personal verification: 1,000 calls/month per supported interface; enterprise: 2,000.', conditionsEn: 'Activate OCR and enter the console to receive the test resource automatically. Translation credentials are different.' },
  { role: 'translation', name: '百度翻译', kind: 'baidu', baseUrl: 'https://fanyi-api.baidu.com/api/trans/vip/translate', model: '', signupUrl: 'https://fanyi-api.baidu.com/manage/developer', credential: 'appPair', id: 'baidu', nameEn: 'Baidu Translate', regionGroup: 'cn', allowance: TRANSLATION_QUOTAS.baidu, quotaEn: 'Standard: 50,000 characters/month; verified Advanced: 1,000,000/month.', conditionsEn: 'Personal verification plus Advanced activation; tiers do not stack.' },
  { role: 'ocr', name: '腾讯云 OCR', kind: 'tencent', baseUrl: 'https://ocr.tencentcloudapi.com', model: 'GeneralBasicOCR', region: 'ap-guangzhou', signupUrl: 'https://console.cloud.tencent.com/ocr/overview', credential: 'tencentOcr', id: 'tencent-ocr', nameEn: 'Tencent Cloud OCR', regionGroup: 'cn', allowance: OCR_QUOTAS.tencent, quotaEn: '1,000 calls/month in each corresponding Basic/Accurate resource pack.', conditionsEn: 'China account, identity verification and OCR activation. Shared-pack rules apply.' },
  { role: 'translation', name: '智谱 GLM-4-Flash', kind: 'openai', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash-250414', signupUrl: 'https://open.bigmodel.cn/', credential: 'apiKey', id: 'zhipu', nameEn: 'Zhipu GLM-4-Flash', regionGroup: 'cn', allowance: TRANSLATION_QUOTAS.zhipu, quotaEn: 'Named free model; no fixed monthly Token allowance.', conditionsEn: 'Only the named model is free; rate/concurrency limits apply.' },
  { role: 'ocr', name: '智谱 GLM-4V-Flash', kind: 'openai-vision', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4v-flash', prompt: 'Recognize all text in this screenshot. Return only the recognized text.', signupUrl: EXTRA_SERVICE_LINKS.glmVision, credential: 'apiKey', id: 'zhipu-vision', nameEn: 'Zhipu GLM-4V-Flash', regionGroup: 'cn', allowance: glmVisionQuota, quotaEn: 'Named vision model: free; no fixed monthly call allowance.', conditionsEn: 'Images are sent to BigModel. Rate limits apply; other models may charge.' },
  { role: 'translation', name: 'Azure Translator', kind: 'microsoft', baseUrl: 'https://api.cognitive.microsofttranslator.com', model: '', signupUrl: 'https://portal.azure.com/', credential: 'microsoft', id: 'microsoft', nameEn: 'Azure Translator', regionGroup: 'overseas', allowance: TRANSLATION_QUOTAS.microsoft, quotaEn: 'F0: 2,000,000 characters/month.', conditionsEn: 'Create an F0 resource; standard translation and custom training share the quota.' },
  { role: 'ocr', name: 'Google Cloud Vision', kind: 'google', baseUrl: 'https://vision.googleapis.com/v1/images:annotate', model: 'TEXT_DETECTION', signupUrl: 'https://console.cloud.google.com/apis/credentials', credential: 'apiKey', id: 'google-ocr', nameEn: 'Google Cloud Vision', regionGroup: 'overseas', allowance: OCR_QUOTAS.google, quotaEn: 'First 1,000 units/month per Text/Document Text Detection feature.', conditionsEn: 'Billing-enabled project required. Per-image/per-page units, not HTTP requests.' },
  { role: 'translation', name: 'DeepL API Developer', kind: 'deepl', baseUrl: 'https://api-free.deepl.com/v2', model: '', signupUrl: 'https://www.deepl.com/your-account/keys', credential: 'apiKey', id: 'deepl', nameEn: 'DeepL API Developer', regionGroup: 'overseas', allowance: TRANSLATION_QUOTAS.deepl, quotaEn: 'New Developer: 1,000,000 characters total, no monthly reset.', conditionsEn: 'Legacy Free: 500,000/month for existing accounts only; no new signups.' },
  { role: 'ocr', name: 'Azure AI Vision', kind: 'azure-vision', baseUrl: '', model: 'read', signupUrl: EXTRA_SERVICE_LINKS.azureVisionOverview, credential: 'azureVision', id: 'azure-ocr', nameEn: 'Azure AI Vision', regionGroup: 'overseas', allowance: OCR_QUOTAS['azure-vision'], quotaEn: 'F0: 5,000 transactions/month; 20 transactions/minute.', conditionsEn: 'Select F0 and your own resource endpoint; availability depends on region.' },
  { id: 'volcengine', role: 'translation', regionGroup: 'cn', name: '火山引擎机器翻译', nameEn: 'Volcengine Translation', kind: 'volcengine', baseUrl: 'https://translate.volcengineapi.com', model: '', region: 'cn-beijing', signupUrl: EXTRA_SERVICE_LINKS.volcengineKeys, credential: 'appPair', allowance: TRANSLATION_QUOTAS.volcengine, quotaEn: 'First 2,000,000 text characters/month.', conditionsEn: 'Activate machine translation; identity verification, sales contract and AccessKey required. Default post-paid billing; not Ark LLM credits.' },
  { id: 'aliyun', role: 'translation', regionGroup: 'cn', name: '阿里云机器翻译', nameEn: 'Alibaba Cloud Translation', kind: 'aliyun', baseUrl: 'https://mt.aliyuncs.com', model: '', region: 'cn-hangzhou', signupUrl: EXTRA_SERVICE_LINKS.aliyunKeys, credential: 'appPair', allowance: TRANSLATION_QUOTAS.aliyun, quotaEn: 'General edition: 1,000,000 characters/month.', conditionsEn: 'Main-account quota shared by subaccounts; resets monthly, does not roll over. Usage above quota is billed.' },
  { id: 'ocrspace', role: 'ocr', regionGroup: 'overseas', name: 'OCR.space', nameEn: 'OCR.space', kind: 'ocrspace', baseUrl: 'https://api.ocr.space', model: '2', signupUrl: 'https://ocr.space/ocrapi', credential: 'apiKey', allowance: OCR_QUOTAS.ocrspace, quotaEn: 'Engines 1/2: 25,000 requests/month; 500/day/IP; 1 MB/file.', conditionsEn: 'Use your own API key, never the public sample key. Daily and monthly limits both apply.' },
  { id: 'qwen-trial', role: 'translation', regionGroup: 'cn', name: '百炼通义千问 · 限时新人额度', nameEn: 'Qwen · introductory trial', kind: 'openai', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-plus', signupUrl: 'https://bailian.console.aliyun.com/', credential: 'apiKey', allowance: TRANSLATION_QUOTAS.qwen, quotaEn: 'Eligible Beijing models: typically 1,000,000 Tokens/model, once, valid for 90 days.', conditionsEn: 'First-time eligible accounts/models only. Input/output share quota. Enable stop-when-free-quota-exhausted in Bailian.' },
  { id: 'youdao', role: 'translation', regionGroup: 'cn', name: '有道智云翻译 · 一次性体验金', nameEn: 'Youdao Translation · one-time credit', kind: 'youdao', baseUrl: 'https://openapi.youdao.com/api', model: '', signupUrl: 'https://ai.youdao.com/console/', credential: 'youdaoPair', allowance: TRANSLATION_QUOTAS.youdao, quotaEn: 'New account: CNY 10; identity verification: additional CNY 40, one time.', conditionsEn: 'Translation and OCR share the account credit, not separate monthly allowances. Eligibility and expiry follow your account.' },
  { id: 'youdao-ocr', role: 'ocr', regionGroup: 'cn', name: '有道智云 OCR · 一次性体验金', nameEn: 'Youdao OCR · one-time credit', kind: 'youdao', baseUrl: 'https://openapi.youdao.com/ocrapi', model: 'general', signupUrl: 'https://ai.youdao.com/console/', credential: 'youdaoPair', allowance: OCR_QUOTAS.youdao, quotaEn: 'New account: CNY 10; identity verification: additional CNY 40, one time.', conditionsEn: 'Same credit pool as Youdao Translation; do not count it twice. Check account expiry and eligible products.' },

  { id: 'qianfan-trial', role: 'translation', regionGroup: 'cn', name: "百度千帆 · 新人试用", nameEn: "qianfan · introductory trial", kind: 'openai', baseUrl: 'https://qianfan.baidubce.com/v2', model: 'ernie-4.5-turbo-128k', editableModel: true, signupUrl: 'https://console.bce.baidu.com/qianfan/overview', credential: 'apiKey', allowance: TRANSLATION_QUOTAS.qianfan, quotaEn: "Eligible new Qianfan accounts: 1,000,000 Tokens per listed model, once, valid for 3 months.", conditionsEn: "Only named online-inference models; not batch inference or a recurring allowance." },
  { id: 'tokenhub-trial', role: 'translation', regionGroup: 'cn', name: "腾讯 TokenHub · 新人试用", nameEn: "tokenhub · introductory trial", kind: 'openai', baseUrl: 'https://tokenhub.tencentmaas.com/v1', model: 'hy3', editableModel: true, recommendUntil: '2026-12-31', signupUrl: 'https://console.cloud.tencent.com/tokenhub', credential: 'apiKey', allowance: TRANSLATION_QUOTAS.tokenhub, quotaEn: "New language-model trial: 1,000,000 Tokens, valid for 1 year; current enrollment ends 2026-12-31.", conditionsEn: "Main-account sharing; one claim per account/model, not additive. Postpaid usage can charge." },
  { id: 'ark-trial', role: 'translation', regionGroup: 'cn', name: "火山方舟 · 新人试用", nameEn: "ark · introductory trial", kind: 'openai', baseUrl: 'https://ark.cn-beijing.volces.com/api/v3', model: 'doubao-seed-2-1-pro-260915', editableModel: true, signupUrl: 'https://ark.volcengine.com/region:cn-beijing/apikey', credential: 'apiKey', allowance: TRANSLATION_QUOTAS.ark, quotaEn: "New-user model trials; exact quantity and expiry must be confirmed in the activation console.", conditionsEn: "Do not assume an old blanket Token allowance applies. Select a model with available trial quota." },
];
export function servicesFor(region: FreeRegion, role: FreePiece['role'], now = new Date()): readonly FreePiece[] {
  return FREE_SERVICES.filter((item) => item.regionGroup === region && item.role === role && (!item.recommendUntil || new Date(now.getTime() + 8 * 60 * 60 * 1000).toISOString().slice(0, 10) <= item.recommendUntil));
}
export function serviceById(id: string): FreePiece | undefined {
  return FREE_SERVICES.find((item) => item.id === id);
}
