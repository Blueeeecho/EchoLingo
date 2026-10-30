import type { ProviderPresetId } from './provider-presets';
import type { OcrProvider } from './types';

export const SERVICE_QUOTA_CHECKED_ON = '2026-10-29';
export interface ServiceAllowance {
  plan: string;
  amount: number | null;
  unit: 'characters' | 'calls' | 'units' | 'tokens' | 'CNY' | 'none';
  period: 'day' | 'month' | 'once' | 'unmetered' | 'variable';
  conditions: readonly string[];
  expires?: string;
}
export interface ServiceQuota {
  badge: string;
  summary: string;
  details: readonly string[];
  allowances: readonly ServiceAllowance[];
  links: ReadonlyArray<readonly [string, string]>;
  checkedOn: string;
  recommendedModel?: string;
}
const quota = (value: Omit<ServiceQuota, 'checkedOn'>): ServiceQuota => ({ ...value, checkedOn: SERVICE_QUOTA_CHECKED_ON });
const localAllowance: readonly ServiceAllowance[] = [{ plan: '本机处理', amount: null, unit: 'none', period: 'unmetered', conditions: ['无需云账号或 API Key；可用语言与性能取决于当前设备。'] }];
const verifiedQuota = (value: Omit<ServiceQuota, 'checkedOn'>): ServiceQuota => ({ ...value, checkedOn: '2026-10-30' });
const youdao = verifiedQuota({
  badge: '一次性体验金', summary: '新用户注册赠 10 元；实名认证后再赠 40 元。',
  details: ['这是一次性账户体验金，不是每月免费字符或次数；翻译与 OCR 不应分别重复计算。', '领取、适用产品及有效期以账户显示为准；额度用完后按所用接口计费。'],
  allowances: [
    { plan: '新用户注册', amount: 10, unit: 'CNY', period: 'once', conditions: ['限新注册的有道智云账户。'], expires: '以账户体验金规则为准' },
    { plan: '实名认证奖励', amount: 40, unit: 'CNY', period: 'once', conditions: ['需通过实名认证；与注册奖励分开领取。'], expires: '以账户体验金规则为准' },
  ], links: [['官方新用户体验金', 'https://ai.youdao.com/new/newuser-promotion.s']],
});

export const TRANSLATION_QUOTAS: Record<ProviderPresetId, ServiceQuota> = {
  niutrans: verifiedQuota({ badge: '每日免费额度', summary: '小牛注册账户每日 20 万字符（100 积分）。', details: ['需注册自己的账号并取得 API Key；积分、限速及资格以控制台为准。', '不把每日额度累计为月额度；应用采用单次 5,000 UTF-8 字节的保守上限。'], allowances: [{ plan: '注册账户每日额度', amount: 200_000, unit: 'characters', period: 'day', conditions: ['注册账户；每日 100 积分对应 20 万字符，实际账户规则以平台为准。'] }], links: [['官方每日额度', 'https://niutrans.com/text_trans']] }),
  'google-translate': verifiedQuota({ badge: '每月抵扣额度', summary: 'Google Cloud Translation NMT：每月前 50 万字符，按最多 10 美元抵扣。', details: ['Basic 与 Advanced 共用抵扣，不结转；此预设只调用 Basic NMT，不是所有翻译产品都免费。', '需启用 API 和结算；超额可能按量计费，API Key 应限制为 Cloud Translation。'], allowances: [{ plan: 'NMT 月度抵扣', amount: 500_000, unit: 'characters', period: 'month', conditions: ['Basic/Advanced 合计最多 10 美元抵扣；不结转。', '账号需开通 API 与结算；以当前价格和控制台为准。'] }], links: [['官方 NMT 价格', 'https://cloud.google.com/products/translate/pricing']] }),
  caiyun: verifiedQuota({ badge: '限时一次性额度', summary: '彩云新用户一次 100 万字符，有效期 1 个月。', details: ['不是每月刷新；字符包含空格和标点，超过免费额度可能按量计费。', '必须申请自己的正式 Token，不使用公共测试 Token；仅支持官方列出的语言方向。'], allowances: [{ plan: '新用户试用', amount: 1_000_000, unit: 'characters', period: 'once', conditions: ['新注册账户申请小译 Token；按原文字符计量，包含空格和标点。'], expires: '1 个月' }], links: [['官方 API 与试用额度', 'https://docs.caiyunapp.com/lingocloud-api/index.html']] }),

  system: quota({ badge: '本机免费', summary: '本机系统翻译，无云端调用额度。', details: ['适用于 macOS 26 及以上；先在设置中准备所需语言包。', 'Windows 请使用安装包内的中英离线翻译；其他平台以实际支持情况为准。'], allowances: localAllowance, links: [['Apple 系统翻译', 'https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:)']] }),
  offline: quota({ badge: '本机免费', summary: 'Windows 安装包内中英模型，无需账号、密钥或按次付费。', details: ['支持简体中文与英语互译；处理速度取决于电脑性能。'], allowances: localAllowance, links: [['离线模型项目', 'https://github.com/mozilla/translations']] }),
  microsoft: verifiedQuota({
    badge: '每月免费额度', summary: 'Azure Translator F0：每月 200 万字符。',
    details: ['创建 Azure 账号和 Translator 资源时选择 F0（免费）层；可用地域和账号开通条件以 Azure 为准。', '此额度属于 F0，不能当作 S1 付费资源自动附送的额度；字符按服务计量规则统计。'],
    allowances: [{ plan: 'Translator F0', amount: 2_000_000, unit: 'characters', period: 'month', conditions: ['Azure 账号；已创建可用的 F0 Translator 资源。', '免费层的标准翻译与自定义翻译训练共用该额度。'] }],
    links: [['F0 官方额度与计费', 'https://azure.microsoft.com/en-us/pricing/details/translator/']],
  }),
  baidu: verifiedQuota({
    badge: '每月免费额度', summary: '标准版每月 5 万字符；个人认证并开通高级版后每月 100 万字符。',
    details: ['在百度翻译开放平台开通对应版本；认证不会替代服务版本升级。', '标准版与高级版为不同版本，额度不能相加；超出免费量目前按 49 元 / 百万字符计费。', '翻译的 APP ID / 密钥与百度智能云 OCR 凭据不同。'],
    allowances: [
      { plan: '通用文本翻译 · 标准版', amount: 50_000, unit: 'characters', period: 'month', conditions: ['注册百度翻译开放平台并开通标准版；无需个人认证。'] },
      { plan: '通用文本翻译 · 高级版', amount: 1_000_000, unit: 'characters', period: 'month', conditions: ['完成个人认证，并开通高级版。', '与标准版额度不叠加。'] },
    ], links: [['官方开通与当前额度', 'https://fanyi-api.baidu.com/access/0/1']],
  }),
  youdao,
  deepl: verifiedQuota({
    badge: '新客一次性免费', summary: '新 API Developer：累计 100 万字符，用完不重置。',
    details: ['旧 API Free 账户仍为每月 50 万字符，但已停止接受新开通；不要将它当作新用户套餐。', '需要 DeepL API 账号，支持国家/地区和验证条件以注册页面为准；网页或桌面翻译订阅不等于 API 套餐。', '按实际 API 套餐选择请求端点；旧 API Free 使用 api-free.deepl.com。'],
    allowances: [
      { plan: 'API Developer · 新用户', amount: 1_000_000, unit: 'characters', period: 'once', conditions: ['开通 API Developer；累计额度，用完不按月恢复。'] },
      { plan: '旧 API Free · 已有账户', amount: 500_000, unit: 'characters', period: 'month', conditions: ['仅适用于已存在的 API Free 账户；已不能新开通。'] },
    ], links: [['官方 API 套餐与额度', 'https://support.deepl.com/hc/en-us/articles/360021200939-DeepL-API-plans']],
  }),
  libretranslate: quota({ badge: '自托管免费软件', summary: '自己部署不收平台按字符调用费；服务器与运维由自己承担。', details: ['需要自行安装服务与语言模型，或接入已有实例；实例管理员可自行设置访问限制。', '官方托管服务收费，开源软件免费不代表 libretranslate.com 的 API 免费。'], allowances: [{ plan: '自托管实例', amount: null, unit: 'none', period: 'unmetered', conditions: ['自行部署并承担运行资源；实际请求限制由实例管理员设置。'] }], links: [['自托管与托管区别', 'https://docs.libretranslate.com/']] }),
  openai: quota({ badge: '按量计费', summary: 'API 按模型 Token 计费，无适用于所有账号的固定免费额度。', details: ['自定义兼容服务的价格由实际服务商决定，不能套用 OpenAI 的套餐。', '符合条件的 ChatGPT Pro / Business 订阅可主动关联本人 API 组织领取抵扣金；不是所有订阅或账号都具备该权益，额度在相应订阅周期结束时过期。'], allowances: [], links: [['官方 API 价格', 'https://developers.openai.com/api/docs/pricing'], ['订阅 API 抵扣权益', 'https://developers.openai.com/api/docs/guides/chatgpt-api-credits']] }),
  minimax: quota({ badge: '按量或套餐计费', summary: '普通 API 按量收费；订阅密钥消耗已购套餐额度。', details: ['没有适用于所有 API 账号的固定长期免费 Token 额度。', '免费使用网页/官方应用不代表 API 免费；中国站账号、密钥和套餐需匹配。'], allowances: [], links: [['官方套餐与使用范围', 'https://platform.minimax.cn/subscribe/coding-plan']] }),
  deepseek: quota({ badge: '按量计费', summary: '按模型输入、输出及缓存 Token 计费，无固定长期免费额度。', details: ['赠送余额如有发放，以账户实际到账和有效期为准，不能视作每月免费额度。'], allowances: [], links: [['官方模型与价格', 'https://api-docs.deepseek.com/zh-cn/quick_start/pricing/']] }),
  zhipu: verifiedQuota({ badge: '部分模型免费', summary: 'GLM-4-Flash-250414 在官方模型页标为免费，无固定月度 Token 数，其他模型另计。', details: ['免费只针对官方列出的免费模型，并有速率和并发限制，政策可能变化。', '不能把所有智谱模型都当成免费。没有适用于全部模型的固定月度额度。', '标准 API 与 Coding Plan 分别管理。'], allowances: [], recommendedModel: 'glm-4-flash-250414', links: [['免费模型说明', 'https://docs.bigmodel.cn/cn/guide/models/free/glm-4-flash-250414'], ['官方模型说明', 'https://docs.bigmodel.cn/cn/guide/start/model-overview']] }),
  siliconflow: verifiedQuota({ badge: '指定模型免费', summary: 'tencent/Hunyuan-MT-7B 当前输入、输出单价均为 0。', details: ['注册硅基流动中国站、创建 API Key；新服务默认填写 tencent/Hunyuan-MT-7B。', '免费仅限官方价格页标明免费的模型，仍受速率、并发与可用性限制；没有统一月度赠送 Token 量。', '已有服务保留原模型；选择 DeepSeek 等收费模型时按其价格计费。'], allowances: [{ plan: 'tencent/Hunyuan-MT-7B', amount: null, unit: 'tokens', period: 'variable', conditions: ['仅此免费模型，不等于全平台免费。', '受服务速率与并发限制。'] }], recommendedModel: 'tencent/Hunyuan-MT-7B', links: [['官方逐模型价格', 'https://www.siliconflow.cn/pricing']] }),
  volcengine: verifiedQuota({
    badge: '每月免费额度', summary: '文本翻译每月前约 200 万字符。核对于 2026-10，可能变化。',
    details: ['需要火山引擎账号、实名，并按官方流程联系销售签约开通机器翻译；默认后付费。', '这是机器翻译接口，不是火山方舟大模型。', '超出免费层后的价格以控制台为准，不承诺永久免费。'],
    allowances: [{ plan: '文本翻译', amount: 2_000_000, unit: 'characters', period: 'month', conditions: ['公开计费说明中的每月前 200 万字符。', '以控制台当时的额度为准。'] }],
    links: [['计费说明', 'https://docs.volcengine.com/docs/machine-translation/product-billing'], ['文本翻译 API', 'https://docs.volcengine.com/docs/machine-translation/text-translation-api']],
  }),
  aliyun: verifiedQuota({
    badge: '每月免费额度', summary: '通用版约 100 万字符/月。核对于 2026-10，可能变化。',
    details: ['这是阿里云机器翻译，不是百炼通义千问。', '免费额度用完后自动进入后付费；应用不会替你停止服务或承诺有关闭后付费开关。', '不承诺永久免费。'],
    allowances: [{ plan: '机器翻译通用版', amount: 1_000_000, unit: 'characters', period: 'month', conditions: ['主账号额度，子账号共享。', '以控制台当时的额度为准。'] }],
    links: [['计费说明', 'https://help.aliyun.com/zh/machine-translation/product-overview/billing-overview'], ['调用说明', 'https://help.aliyun.com/zh/machine-translation/developer-reference/api-reference-machine-translation-universal-version-call-guide']],
  }),
  qwen: verifiedQuota({ badge: '限时新人额度', summary: '北京地域参与活动的模型通常每模型 100 万 Token，一次性、90 天有效。', details: ['仅北京地域且参与新人额度的模型适用；新加坡等地域没有该免费额度。', '模型与快照版本分别计算；具体余量以控制台为准，输入与输出共用同一额度。', '已认证账号在额度用完或过期后可自动转按量计费，建议在百炼控制台开启“免费额度用完即停”。'], allowances: [{ plan: '参与新人额度的模型（通常）', amount: 1_000_000, unit: 'tokens', period: 'once', conditions: ['首次开通百炼；仅北京地域符合条件的模型。', '具体模型额度以控制台显示为准；不跨模型合并。'], expires: '自开通、模型发布或申请通过的较晚日期起 90 天' }], links: [['官方新人额度与用完即停', 'https://help.aliyun.com/zh/model-studio/new-free-quota/']] }),
};

export const OCR_QUOTAS: Record<OcrProvider['kind'] | 'local', ServiceQuota> = {
  local: quota({ badge: '本机免费', summary: '本机 OCR 不上传截图，无云端调用额度。', details: ['使用当前系统的本机识别能力；语言包和可识别语言以设备支持情况为准。'], allowances: localAllowance, links: [] }),
  baidu: verifiedQuota({ badge: '每月免费额度', summary: '标准版 / 高精度版：个人认证各 1000 次/月，企业认证各 2000 次/月。', details: ['开通百度智能云文字识别并完成实名认证，进入控制台后按官方规则自动发放对应接口测试资源。', '这里对应 general_basic 与 accurate_basic；月额度不结转，成功和失败调用都会消耗测试资源。'], allowances: [
    { plan: '个人认证 · 每个已支持接口', amount: 1000, unit: 'calls', period: 'month', conditions: ['开通 OCR、个人实名认证，进入控制台查看自动发放的对应接口测试资源。'] },
    { plan: '企业认证 · 每个已支持接口', amount: 2000, unit: 'calls', period: 'month', conditions: ['完成企业实名认证；与个人额度不是叠加关系。'] },
  ], links: [['官方 OCR 免费测试资源', 'https://ai.baidu.com/ai-doc/OCR/fk3h7xu7h']] }),
  tencent: verifiedQuota({ badge: '每月免费额度', summary: '通用印刷体 / 高精度识别：各 1000 次/月。', details: ['适用于腾讯云中国站；注册、实名认证并开通 OCR 后查看对应资源包。', '免费资源包当月有效、每月发放，不结转；一年未使用的账号可能暂停发放；同一共享资源包内的接口共同扣减，不能重复相加。', '免费额度用完后可能进入按量计费，使用前检查控制台计费设置。'], allowances: [{ plan: 'GeneralBasicOCR / GeneralAccurateOCR 对应资源包', amount: 1000, unit: 'calls', period: 'month', conditions: ['腾讯云中国站账号、实名认证、开通 OCR。', '每个对应资源包当月有效；遵循接口共享规则。'] }], links: [['官方 OCR 免费额度', 'https://cloud.tencent.com/document/product/866/35945']] }),
  youdao,
  google: verifiedQuota({ badge: '每月免费额度', summary: 'Text / Document Text Detection：各功能每月前 1000 units 免费。', details: ['需要 Google Cloud 项目、启用 Vision API 和结算，并配置受限 API Key。', '1 个功能处理 1 张图片为 1 unit；多页文件按页计量，不能把 1000 units 当作 1000 个批量 HTTP 请求。', '超出免费层按实际功能计费；其他 Google Cloud 产品费用另计。'], allowances: [{ plan: 'TEXT_DETECTION / DOCUMENT_TEXT_DETECTION 每个功能', amount: 1000, unit: 'units', period: 'month', conditions: ['项目启用 Cloud Vision 与结算。', '每功能、每图计量；多页文件逐页计量。'] }], links: [['Cloud Vision 官方价格', 'https://cloud.google.com/vision/pricing']] }),
  'openai-vision': quota({ badge: '由模型服务商计费', summary: '图片和输出通常按 Token 或所选服务规则计费，无统一免费次数。', details: ['图片会上传到你明确选择的模型服务商；免费额度、模型支持和账号条件按实际服务商核对。', 'OpenAI 官方 API 价格不代表所有 OpenAI 兼容视觉服务的价格。'], allowances: [], links: [['OpenAI 官方 API 价格', 'https://developers.openai.com/api/docs/pricing']] }),
  'http-json': quota({ badge: '由网关运营方决定', summary: '没有统一免费额度，收费与调用限制由所接入的网关决定。', details: ['填写前向运营方确认单次费用、月额度、数据处理方式和认证要求。'], allowances: [], links: [] }),
  'azure-vision': verifiedQuota({ badge: '每月免费额度', summary: 'F0 约 5000 次/月。核对于 2026-10，部分区域没有该层。', details: ['创建资源时选择 F0。不要假设付费层也包含同样的免费次数。', '额度用完后的行为以 Azure 资源设置为准。'], allowances: [{ plan: 'Computer Vision F0', amount: 5000, unit: 'calls', period: 'month', conditions: ['资源为 F0。', '以价格页和资源所在区域为准。'] }], links: [['Vision 价格', 'https://azure.microsoft.com/en-us/pricing/details/computer-vision/']] }),
  ocrspace: verifiedQuota({ badge: '每月免费额度', summary: 'Engine 1/2 约 25000 次/月，并且每 IP 约 500 次/日。核对于 2026-10。', details: ['必须使用你自己的 API Key，应用不会内置或默认公共示例密钥。', '免费层文件大约 1 MB。额度可能变化，不承诺永久免费。'], allowances: [{ plan: 'Engine 1 / Engine 2', amount: 25000, unit: 'calls', period: 'month', conditions: ['自有 API Key。', '另有大约每日 500 次的 IP 限制。'] }], links: [['OCR.space API', 'https://ocr.space/ocrapi']] }),
};
export const EXTRA_SERVICE_LINKS = {
  geminiKey: 'https://aistudio.google.com/apikey',
  geminiPricing: 'https://ai.google.dev/gemini-api/docs/pricing',
  geminiOpenAI: 'https://ai.google.dev/gemini-api/docs/openai',
  glmVision: 'https://docs.bigmodel.cn/cn/guide/models/free/glm-4v-flash',
  freeSetupZh: 'https://github.com/Blueeeecho/EchoLingo/blob/main/docs/free-setup.zh-CN.md',
  freeSetupEn: 'https://github.com/Blueeeecho/EchoLingo/blob/main/docs/free-setup.md',
  ocrSpaceHome: 'https://ocr.space/',
  azureVisionOverview: 'https://learn.microsoft.com/azure/ai-services/computer-vision/overview',
  volcengineKeys: 'https://console.volcengine.com/iam/keymanage/',
  aliyunKeys: 'https://ram.console.aliyun.com/manage/ak',
} as const;

export function recommendedTranslationPresets(platform: string): readonly ProviderPresetId[] {
  const local: ProviderPresetId[] = ['macos', 'darwin'].includes(platform.toLowerCase()) ? ['system']
    : ['windows', 'win32'].includes(platform.toLowerCase()) ? ['offline'] : [];
  return [...local, 'microsoft', 'baidu', 'siliconflow'];
}
