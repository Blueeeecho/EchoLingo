import { EXTRA_SERVICE_LINKS } from './service-quotas';

export type FreeRegion = 'cn' | 'overseas';
export type FreeCredential = 'apiKey' | 'appPair' | 'ocrPair' | 'tencentOcr' | 'microsoft' | 'azureVision';

export interface FreePiece {
  role: 'translation' | 'ocr';
  name: string;
  kind: string;
  baseUrl: string;
  model: string;
  region?: string;
  prompt?: string;
  signupUrl: string;
  quotaZh: string;
  quotaEn: string;
  warningZh?: string;
  warningEn?: string;
  credential: FreeCredential;
}

export interface FreeCombo {
  id: string;
  region: FreeRegion;
  titleZh: string;
  titleEn: string;
  detailZh: string;
  detailEn: string;
  pieces: readonly FreePiece[];
}

const checked = '核对于 2026-10，额度会变，请以控制台当时的说明为准。';
const checkedEn = 'Checked in 2026-10. Quotas change; the vendor console is authoritative.';

export const FREE_COMBOS: readonly FreeCombo[] = [
  {
    id: 'cn-siliconflow-baidu-ocr', region: 'cn',
    titleZh: '硅基流动 Hunyuan-MT + 百度 OCR', titleEn: 'SiliconFlow Hunyuan-MT + Baidu OCR',
    detailZh: `翻译模型 tencent/Hunyuan-MT-7B 在价格页的输入/输出单价为 0。百度 OCR 个人认证约 1000 次/月。${checked}`,
    detailEn: `tencent/Hunyuan-MT-7B is listed at price 0 on the vendor pricing page. Baidu OCR personal auth is about 1,000 calls/month. ${checkedEn}`,
    pieces: [
      { role: 'translation', name: '硅基流动', kind: 'openai', baseUrl: 'https://api.siliconflow.cn/v1', model: 'tencent/Hunyuan-MT-7B', signupUrl: 'https://cloud.siliconflow.cn/', credential: 'apiKey', quotaZh: `指定模型当前单价为 0，仍有限流。${checked}`, quotaEn: `The named model is currently priced at 0 and still rate-limited. ${checkedEn}` },
      { role: 'ocr', name: '百度 OCR', kind: 'baidu', baseUrl: 'https://aip.baidubce.com', model: 'general_basic', signupUrl: 'https://console.bce.baidu.com/ai/#/ai/ocr/overview/index', credential: 'ocrPair', quotaZh: `个人认证约 1000 次/月。翻译 APP ID 不能用在这里。${checked}`, quotaEn: `About 1,000 calls/month after personal verification. A Baidu Translate APP ID does not work here. ${checkedEn}` },
    ],
  },
  {
    id: 'cn-baidu-tencent-ocr', region: 'cn',
    titleZh: '百度翻译 + 腾讯 OCR', titleEn: 'Baidu Translate + Tencent OCR',
    detailZh: `个人认证高级版约 100 万字符/月。腾讯 OCR 约 1000 次/月，用完后可能按量计费。${checked}`,
    detailEn: `Advanced personal auth is about 1 million characters/month. Tencent OCR is about 1,000 calls/month and may switch to paid usage. ${checkedEn}`,
    pieces: [
      { role: 'translation', name: '百度翻译', kind: 'baidu', baseUrl: 'https://fanyi-api.baidu.com/api/trans/vip/translate', model: '', signupUrl: 'https://fanyi-api.baidu.com/manage/developer', credential: 'appPair', quotaZh: `标准版约 5 万字符/月，高级版约 100 万。与百度 OCR 不是同一套密钥。${checked}`, quotaEn: `Standard is about 50,000 characters/month; advanced is about 1 million. Not the same keys as Baidu OCR. ${checkedEn}` },
      { role: 'ocr', name: '腾讯云 OCR', kind: 'tencent', baseUrl: 'https://ocr.tencentcloudapi.com', model: 'GeneralBasicOCR', region: 'ap-guangzhou', signupUrl: 'https://console.cloud.tencent.com/ocr/overview', credential: 'tencentOcr', warningZh: '免费额度用完后可能按量计费，请检查控制台计费设置。', warningEn: 'After the free quota, billing may continue at paid rates. Check the console billing settings.', quotaZh: `通用印刷体约 1000 次/月。${checked}`, quotaEn: `About 1,000 general-print calls/month. ${checkedEn}` },
    ],
  },
  {
    id: 'cn-zhipu', region: 'cn',
    titleZh: '智谱 GLM-4-Flash + GLM-4V-Flash', titleEn: 'Zhipu GLM-4-Flash + GLM-4V-Flash',
    detailZh: `同一开放平台账号。2026-10 的模型页把这两个 Flash 标为免费，仍有速率限制。${checked}`,
    detailEn: `One BigModel account. As of 2026-10 the vendor lists these Flash models as free, with rate limits. ${checkedEn}`,
    pieces: [
      { role: 'translation', name: '智谱 GLM-4-Flash', kind: 'openai', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash', signupUrl: 'https://open.bigmodel.cn/', credential: 'apiKey', quotaZh: `仅官方列出的免费模型，不是全部智谱模型。${checked}`, quotaEn: `Only models the vendor lists as free, not every Zhipu model. ${checkedEn}` },
      { role: 'ocr', name: '智谱 GLM-4V-Flash', kind: 'openai-vision', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4v-flash', prompt: 'Recognize all text in this screenshot. Return only the recognized text.', signupUrl: EXTRA_SERVICE_LINKS.glmVision, credential: 'apiKey', quotaZh: `视觉模型页标为免费，图片会上传到智谱。${checked}`, quotaEn: `The vision model page lists it as free. The image is uploaded to Zhipu. ${checkedEn}` },
    ],
  },
  {
    id: 'os-azure-google', region: 'overseas',
    titleZh: 'Azure Translator F0 + Google Vision', titleEn: 'Azure Translator F0 + Google Vision',
    detailZh: `F0 约 200 万字符/月。Google Vision 每个文字功能约 1000 units/月。${checked}`,
    detailEn: `F0 is about 2 million characters/month. Google Vision is about 1,000 units/month per text feature. ${checkedEn}`,
    pieces: [
      { role: 'translation', name: 'Azure Translator', kind: 'microsoft', baseUrl: 'https://api.cognitive.microsofttranslator.com', model: '', signupUrl: 'https://portal.azure.com/', credential: 'microsoft', quotaZh: `创建资源时选择 F0。${checked}`, quotaEn: `Choose the F0 tier when creating the resource. ${checkedEn}` },
      { role: 'ocr', name: 'Google Cloud Vision', kind: 'google', baseUrl: 'https://vision.googleapis.com/v1/images:annotate', model: 'TEXT_DETECTION', signupUrl: 'https://console.cloud.google.com/apis/credentials', credential: 'apiKey', quotaZh: `Text Detection 约 1000 units/月，通常需要结算账号。${checked}`, quotaEn: `Text Detection is about 1,000 units/month and usually needs a billing account. ${checkedEn}` },
    ],
  },
  {
    id: 'os-deepl-azure-vision', region: 'overseas',
    titleZh: 'DeepL API Free + Azure AI Vision', titleEn: 'DeepL API Free + Azure AI Vision',
    detailZh: `新 API Developer 约累计 100 万字符，用完不按月重置。Azure AI Vision F0 约 5000 次/月。${checked}`,
    detailEn: `New API Developer is about 1 million characters total, not a monthly reset. Azure AI Vision F0 is about 5,000 calls/month. ${checkedEn}`,
    pieces: [
      { role: 'translation', name: 'DeepL API Free', kind: 'deepl', baseUrl: 'https://api-free.deepl.com/v2', model: '', signupUrl: 'https://www.deepl.com/your-account/keys', credential: 'apiKey', quotaZh: `旧的每月 Free 已不能新开。${checked}`, quotaEn: `The old monthly Free plan is not open to new signups. ${checkedEn}` },
      { role: 'ocr', name: 'Azure AI Vision', kind: 'azure-vision', baseUrl: '', model: 'read', signupUrl: EXTRA_SERVICE_LINKS.azureVisionOverview, credential: 'azureVision', quotaZh: `填写你自己的 *.cognitiveservices.azure.com 终结点。F0 约 5000 次/月，部分区域没有。${checked}`, quotaEn: `Use your own *.cognitiveservices.azure.com endpoint. F0 is about 5,000 calls/month and is missing in some regions. ${checkedEn}` },
    ],
  },
  {
    id: 'os-gemini-ocrspace', region: 'overseas',
    titleZh: 'Gemini 免费层 + OCR.space', titleEn: 'Gemini free tier + OCR.space',
    detailZh: `Gemini 部分 Flash 模型在价格页标为 Free of charge。OCR.space 必须用你自己的 Key。${checked}`,
    detailEn: `Some Gemini Flash models are marked Free of charge on the pricing page. OCR.space requires your own key. ${checkedEn}`,
    pieces: [
      { role: 'translation', name: 'Gemini', kind: 'openai', baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai', model: 'gemini-2.0-flash', signupUrl: EXTRA_SERVICE_LINKS.geminiKey, credential: 'apiKey', quotaZh: `以 Gemini 价格页当时标为免费的模型为准，可稍后在设置里改模型名。${checked}`, quotaEn: `Use a model the Gemini pricing page currently marks as free. You can change the model name later. ${checkedEn}` },
      { role: 'ocr', name: 'OCR.space', kind: 'ocrspace', baseUrl: 'https://api.ocr.space', model: '2', signupUrl: 'https://ocr.space/ocrapi', credential: 'apiKey', warningZh: '不要填写网站上的公共示例密钥。', warningEn: 'Do not paste the public sample key from the website.', quotaZh: `Engine 2 约 25000 次/月，另有每日 IP 限制。${checked}`, quotaEn: `Engine 2 is about 25,000 calls/month, plus a daily IP limit. ${checkedEn}` },
    ],
  },
];

export function combosFor(region: FreeRegion): readonly FreeCombo[] {
  return FREE_COMBOS.filter((combo) => combo.region === region);
}

export function comboById(id: string): FreeCombo | undefined {
  return FREE_COMBOS.find((combo) => combo.id === id);
}
