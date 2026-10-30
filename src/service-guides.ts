import type { ServiceQuota } from './service-quotas';
import { renderServiceQuota } from './service-quota-ui';
import type { ProviderPresetId } from './provider-presets';
import type { OcrProvider } from './types';

export interface ServiceGuide { steps: readonly string[]; links: ReadonlyArray<readonly [string, string]> }
// Official public setup pages; no account access is needed to show this help.
export const TRANSLATION_GUIDES: Record<ProviderPresetId, ServiceGuide> = {
  "qianfan": { steps: ["在平台控制台开通标准 API，创建自己的 API Key；不要使用其他服务或订阅专属凭据。", "确认账号可用的试用模型、余额及到期日；在向导中手动填写已确认的模型 ID，再测试连接。"], links: [["控制台 / API Key", "https://console.bce.baidu.com/qianfan/overview"], ["官方协议", "https://ai.baidu.com/ai-doc/WENXINWORKSHOP/2m3fihw8s"]] },
  "tokenhub": { steps: ["在平台控制台开通标准 API，创建自己的 API Key；不要使用其他服务或订阅专属凭据。", "确认账号可用的试用模型、余额及到期日；在向导中手动填写已确认的模型 ID，再测试连接。"], links: [["控制台 / API Key", "https://console.cloud.tencent.com/tokenhub"], ["官方协议", "https://cloud.tencent.com/document/product/1823/130079"]] },
  "ark": { steps: ["在平台控制台开通标准 API，创建自己的 API Key；不要使用其他服务或订阅专属凭据。", "确认账号可用的试用模型、余额及到期日；在向导中手动填写已确认的模型 ID，再测试连接。"], links: [["控制台 / API Key", "https://ark.volcengine.com/region:cn-beijing/apikey"], ["官方协议", "https://docs.volcengine.com/docs/ark/text-generation"]] },

  system: { steps: ['在设置的“系统翻译 · 语言包”中检查语言对，按需点击“准备语言包”。', '可用性以当前系统检查结果为准；无需云账号或密钥。'], links: [['系统 API 文档', 'https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:)']] },
  offline: { steps: ['Windows 预览安装包包含中英离线模型，添加并启用即可。', '无需账号或密钥；其他语言请另选服务。'], links: [['项目与模型说明', 'https://github.com/mozilla/translations']] },
  baidu: { steps: ['登录百度翻译开放平台，注册开发者并开通“通用文本翻译 API”。', '从管理控制台取得 APP ID 和密钥，完整填写下方两项。百度 OCR 的 API Key 不能用于此处。'], links: [['注册 / 开通', 'https://fanyi-api.baidu.com/access/0/1'], ['管理控制台', 'https://fanyi-api.baidu.com/manage/developer'], ['API 文档', 'https://fanyi-api.baidu.com/doc/21']] },
  youdao: { steps: ['登录有道智云，在控制台开通文本翻译服务并创建、关联应用。', '在应用管理复制应用 ID 和应用密钥，完整填写下方两项。'], links: [['账号 / 开通', 'https://ai.youdao.com/'], ['应用控制台', 'https://ai.youdao.com/console/'], ['API 文档', 'https://ai.youdao.com/DOCSIRMA/html/trans/api/wbfy/index.html']] },
  microsoft: { steps: ['登录 Azure，创建可使用公共全球端点的 Translator 资源。', '在“密钥和终结点”复制密钥；区域或多服务资源同时填写地域。全球单服务资源可留空。'], links: [['账号 / 开通', 'https://azure.microsoft.com/products/ai-services/ai-translator'], ['Azure 控制台', 'https://portal.azure.com/'], ['API 文档', 'https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/v3/translate'], ['认证与地域', 'https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/authentication']] },
  deepl: { steps: ['注册并开通 DeepL API 套餐，在账户中取得 API Key。', '按套餐选择 api-free.deepl.com 或 api.deepl.com；DeepL 网页翻译订阅与 API 套餐有区别。'], links: [['账号 / 开通', 'https://www.deepl.com/pro-api'], ['账户与密钥', 'https://www.deepl.com/your-account/keys'], ['API 文档', 'https://developers.deepl.com/api-reference/translate/request-translation']] },
  libretranslate: { steps: ['准备自己的 LibreTranslate 实例，或向所选实例运营方取得访问权限。', '填写实例地址；API Key 是否必需由该实例决定。'], links: [['官方服务', 'https://libretranslate.com/'], ['部署 / API 文档', 'https://docs.libretranslate.com/guides/api_usage/']] },
  openai: { steps: ['在服务商平台开通 API 并创建密钥，填入该服务的地址与可用模型。', '使用 OpenAI 官方服务时可从下方平台创建 Key；其他兼容服务使用各自账号和文档。'], links: [['账号 / 控制台', 'https://platform.openai.com/'], ['API 密钥', 'https://platform.openai.com/api-keys'], ['API 文档', 'https://developers.openai.com/api/reference/overview']] },
  minimax: { steps: ['登录 MiniMax 中国站开放平台，开通相应 API 或套餐并创建密钥。', '填写该账号可用的模型；中国站 Key 与国际站不可混用。'], links: [['账号 / 控制台', 'https://platform.minimax.cn/'], ['API 文档', 'https://platform.minimax.cn/docs/api-reference/text-openai-api']] },
  deepseek: { steps: ['登录 DeepSeek 开放平台并创建 API Key。', '填写平台实际可用的模型；额度与开通条件以控制台为准。'], links: [['账号 / 控制台', 'https://platform.deepseek.com/'], ['API 密钥', 'https://platform.deepseek.com/api_keys'], ['API 文档', 'https://api-docs.deepseek.com/']] },
  zhipu: { steps: ['登录智谱 BigModel 开放平台，开通模型并创建 API Key。', '填写实际可用模型；标准 API 与 Coding Plan 的端点和额度可能不同。'], links: [['账号 / 控制台', 'https://open.bigmodel.cn/'], ['API 文档', 'https://docs.bigmodel.cn/cn/guide/develop/openai/introduction']] },
  siliconflow: { steps: ['登录硅基流动中国站控制台并创建 API Key。', '从模型列表复制完整模型 ID，确认该账号可调用后填写。'], links: [['账号 / 控制台', 'https://cloud.siliconflow.cn/'], ['API 文档', 'https://docs.siliconflow.cn/docs/api/chat-completions-post']] },
  qwen: { steps: ['登录阿里云百炼，开通模型服务并在对应地域创建 API Key。', '选择相同地域与业务空间，填写可用模型。此项为百炼大模型，不能填写阿里机器翻译 AccessKey。'], links: [['账号 / 控制台', 'https://bailian.console.aliyun.com/'], ['API 文档', 'https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope'], ['创建 API Key', 'https://help.aliyun.com/zh/model-studio/get-api-key']] },
  volcengine: { steps: ['注册火山引擎并完成实名，开通机器翻译。', '在访问控制创建 AccessKey ID 和 Secret Access Key。这不是大模型 Key。', '免费层说明核对于 2026-10，以控制台为准，不保证长期不变。'], links: [['机器翻译 API', 'https://docs.volcengine.com/docs/machine-translation/text-translation-api'], ['计费说明', 'https://docs.volcengine.com/docs/machine-translation/product-billing'], ['AccessKey', 'https://console.volcengine.com/iam/keymanage/']] },
  aliyun: { steps: ['注册阿里云并完成实名，开通机器翻译通用版。不要和百炼通义千问的 API Key 混用。', '在访问控制创建 AccessKey ID 和 AccessKey Secret。', '2026-10 的公开说明是通用版约 100 万字符/月。额度用完后可能按量计费，请在控制台关闭后付费或设置用完即停。'], links: [['调用说明', 'https://help.aliyun.com/zh/machine-translation/developer-reference/api-reference-machine-translation-universal-version-call-guide'], ['计费说明', 'https://help.aliyun.com/zh/machine-translation/product-overview/billing-overview'], ['AccessKey', 'https://ram.console.aliyun.com/manage/ak']] },
};
export const OCR_GUIDES: Record<OcrProvider['kind'], ServiceGuide> = {
  baidu: { steps: ['登录百度智能云，开通文字识别并创建 OCR 应用。', '从应用列表复制 API Key 和 Secret Key，完整填写两项；与百度翻译 APP ID 分开。'], links: [['账号 / 开通', 'https://cloud.baidu.com/product/ocr'], ['OCR 控制台', 'https://console.bce.baidu.com/ai/#/ai/ocr/overview/index'], ['API 文档', 'https://cloud.baidu.com/doc/OCR/s/zk3h7xz52']] },
  tencent: { steps: ['登录腾讯云，开通文字识别并为账号配置 OCR 调用权限。', '在访问管理中取得 SecretId、SecretKey，按需填写临时 SessionToken；选择服务地域。'], links: [['账号 / 开通', 'https://cloud.tencent.com/product/ocr'], ['OCR 控制台', 'https://console.cloud.tencent.com/ocr/overview'], ['访问密钥', 'https://console.cloud.tencent.com/cam/capi'], ['API 文档', 'https://cloud.tencent.com/document/product/866/33526']] },
  youdao: { steps: ['登录有道智云，开通通用文字识别并创建、关联应用。', '在应用管理复制应用 ID 和应用密钥，完整填写两项。'], links: [['账号 / 开通', 'https://ai.youdao.com/'], ['应用控制台', 'https://ai.youdao.com/console/'], ['API 文档', 'https://ai.youdao.com/DOCSIRMA/html/ocr/api/tyocr/index.html']] },
  google: { steps: ['登录 Google Cloud，选择项目、配置结算并启用 Cloud Vision API。', '在“API 和服务 → 凭据”创建 API Key 并限制为 Cloud Vision API，填入下方；调用与额度以控制台为准。'], links: [['账号 / 开通', 'https://cloud.google.com/vision'], ['API / 凭据控制台', 'https://console.cloud.google.com/apis/credentials'], ['OCR 文档', 'https://cloud.google.com/vision/docs/ocr'], ['API Key 用法', 'https://cloud.google.com/docs/authentication/api-keys-use']] },
  'openai-vision': { steps: ['在视觉模型服务商平台开通 API，创建密钥并确认模型支持图片。', '填写该服务的兼容地址和模型；截图会上传到此服务。'], links: [['OpenAI 账号 / 控制台', 'https://platform.openai.com/'], ['API 密钥', 'https://platform.openai.com/api-keys'], ['API 文档', 'https://developers.openai.com/api/reference/overview']] },
  'http-json': { steps: ['向你信任的 OCR 网关运营方取得地址、认证方式和请求格式。', '按网关文档填写图片模板与响应路径；可先查看 JSON Pointer 格式。'], links: [['JSON Pointer 标准', 'https://www.rfc-editor.org/rfc/rfc6901']] },
  'azure-vision': { steps: ['在 Azure 创建 Computer Vision 或 AI Vision 资源，并选择 F0 免费层。', '复制资源终结点（https://你的资源名.cognitiveservices.azure.com）和密钥。', 'F0 大约 5000 次/月的说明核对于 2026-10，部分区域没有 F0。不要把密钥留在公共示例里。'], links: [['Vision 价格', 'https://azure.microsoft.com/en-us/pricing/details/cognitive-services/computer-vision/'], ['Vision 概述', 'https://learn.microsoft.com/azure/ai-services/computer-vision/overview'], ['Azure 门户', 'https://portal.azure.com/']] },
  ocrspace: { steps: ['在 OCR.space 注册并创建你自己的 API Key。', '不要使用网站上的公共示例密钥。免费层额度核对于 2026-10，约 Engine 1/2 每月 25000 次、每 IP 每天 500 次，可能变化。'], links: [['OCR.space API', 'https://ocr.space/ocrapi'], ['OCR.space', 'https://ocr.space/']] },
};
export function renderServiceGuide(container: HTMLElement, guide: ServiceGuide, quota?: ServiceQuota, currentModel = ''): void {
  const steps = document.createElement('ol');
  for (const text of guide.steps) { const item = document.createElement('li'); item.textContent = text; steps.append(item); }
  const links = document.createElement('div'); links.className = 'service-guide-links';
  for (const [label, url] of guide.links) { const anchor = document.createElement('a'); anchor.textContent = `${label} ↗`; anchor.href = url; anchor.target = '_blank'; anchor.rel = 'noopener noreferrer'; anchor.dataset.serviceLink = 'true'; links.append(anchor); }
  container.replaceChildren(...(quota ? [renderServiceQuota(quota, currentModel)] : []), steps, links);
}
