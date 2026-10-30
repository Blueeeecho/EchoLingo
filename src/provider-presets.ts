import type { Provider, ProviderKind } from './types';
import { isNativeTranslation, TRANSLATION_NATIVE_URLS } from './translation-credentials';

export type ProviderPresetId = 'system' | 'offline' | 'baidu' | 'youdao' | 'microsoft' | 'openai' | 'minimax' | 'deepseek' | 'zhipu' | 'siliconflow' | 'qwen' | 'deepl' | 'libretranslate' | 'volcengine' | 'aliyun' | 'niutrans' | 'google-translate' | 'caiyun';
export type QwenRegion = 'beijing' | 'singapore';
export interface ProviderPreset {
  id: ProviderPresetId; label: string; name: string; kind: ProviderKind; baseUrl: string; exampleModel: string; help: string; docs: string;
}
// Endpoints verified against the linked vendor documentation on 2026-10-24 (MiniMax: 2026-10-25).
// Model IDs are editable examples, not a statement that a model is newest or available to every account.
export const PROVIDER_PRESETS: readonly ProviderPreset[] = [
  { id: "niutrans", label: "小牛翻译 · 官方机器翻译", name: "小牛翻译", kind: "niutrans", baseUrl: "https://api.niutrans.com/NiuTransServer/translation", exampleModel: "", help: "小牛官方文本翻译 API，填写自己的 API Key；应用保守单次上限为 5,000 UTF-8 字节。", docs: "https://niutrans.com/documents/contents/trans_detection" },
  { id: "google-translate", label: "Google Cloud Translation · 官方机器翻译", name: "Google Cloud Translation", kind: "google-translate", baseUrl: "https://translation.googleapis.com/language/translate/v2", exampleModel: "", help: "Google Cloud Translation Basic v2 的 NMT API，不是 Gemini；填写限制为 Cloud Translation 的 API Key。需开通 API 与结算。", docs: "https://docs.cloud.google.com/translate/docs/reference/rest/v2/translate" },
  { id: "caiyun", label: "彩云小译 · 官方机器翻译", name: "彩云小译", kind: "caiyun", baseUrl: "https://api.interpreter.caiyunai.com/v1/translator", exampleModel: "", help: "彩云小译官方 API。填写自己的 Token；新用户试用不是每月重置，语言方向限官方支持的中外互译。", docs: "https://docs.caiyunapp.com/lingocloud-api/index.html" },

  { id: 'system', label: '系统翻译 · 无需 API Key', name: '系统翻译', kind: 'system', baseUrl: '', exampleModel: '', help: '使用当前系统公开提供的翻译能力，无需 API Key。macOS 26 及以上支持；首次可能需要在设置中准备语言包。其他系统的实际可用性以检查结果为准。', docs: 'https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:)' },
  { id: 'offline', label: '本机离线翻译 · 中英互译', name: '本机离线翻译', kind: 'offline', baseUrl: '', exampleModel: '', help: '使用 Windows 安装包内的 Mozilla 中英模型，无需 API Key 或下载语言包。支持简体中文与英语互译；其他语言请选择系统翻译或 API 服务。', docs: 'https://github.com/mozilla/translations' },
  { id: 'baidu', label: '百度翻译 · 通用文本翻译', name: '百度翻译', kind: 'baidu', baseUrl: TRANSLATION_NATIVE_URLS.baidu, exampleModel: '', help: '百度翻译开放平台的通用文本翻译 API。填写该平台 APP ID 和密钥，与百度智能云 OCR 凭据分开。', docs: 'https://fanyi-api.baidu.com/doc/21' },
  { id: 'youdao', label: '有道智云 · 文本翻译', name: '有道翻译', kind: 'youdao', baseUrl: TRANSLATION_NATIVE_URLS.youdao, exampleModel: '', help: '有道智云文本翻译 API。填写已关联文本翻译服务的应用 ID 和应用密钥。', docs: 'https://ai.youdao.com/DOCSIRMA/html/trans/api/wbfy/index.html' },
  { id: 'microsoft', label: '微软 · Azure Translator', name: '微软翻译', kind: 'microsoft', baseUrl: TRANSLATION_NATIVE_URLS.microsoft, exampleModel: '', help: 'Azure Translator 文本翻译 API，使用全球端点。填写资源密钥；区域或多服务资源还需填写资源地域。不支持仅私网/自定义域名资源。', docs: 'https://learn.microsoft.com/azure/ai-services/translator/text-translation/reference/v3/translate' },
  { id: 'openai', label: 'OpenAI / 自定义兼容接口', name: 'OpenAI 兼容服务', kind: 'openai', baseUrl: 'https://api.openai.com/v1', exampleModel: 'gpt-4o-mini', help: 'OpenAI Chat Completions 兼容协议。可改为你自己的兼容服务地址与模型。', docs: 'https://developers.openai.com/api/reference/overview' },
  { id: 'minimax', label: 'MiniMax · 中国站', name: 'MiniMax', kind: 'openai', baseUrl: 'https://api.minimax.cn/v1', exampleModel: 'MiniMax-M3.1-Flash', help: 'MiniMax 中国站接口，请使用对应地域和账号的 Key；订阅 Key 使用套餐额度。模型可修改，M3.1 Flash 默认深度思考可能增加耗时。', docs: 'https://platform.minimax.cn/docs/api-reference/text-openai-api' },
  { id: 'deepseek', label: 'DeepSeek', name: 'DeepSeek', kind: 'openai', baseUrl: 'https://api.deepseek.com', exampleModel: 'deepseek-flash', help: 'DeepSeek 官方 OpenAI 兼容接口，填写 DeepSeek 平台 API Key。模型名称可修改。', docs: 'https://api-docs.deepseek.com/' },
  { id: 'zhipu', label: '智谱 · BigModel', name: '智谱', kind: 'openai', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', exampleModel: 'glm-5.3', help: '智谱开放平台标准 API。请使用对应平台的 API Key 和已开通模型；Coding Plan 配额与端点可能不同。', docs: 'https://docs.bigmodel.cn/cn/guide/develop/openai/introduction' },
  { id: 'siliconflow', label: '硅基流动 · SiliconFlow', name: '硅基流动', kind: 'openai', baseUrl: 'https://api.siliconflow.cn/v1', exampleModel: 'tencent/Hunyuan-MT-7B', help: '硅基流动中国站接口。默认翻译模型 tencent/Hunyuan-MT-7B 当前输入与输出单价为 0，仍受平台限流；其他模型按各自价格计费。已有服务保留原模型。', docs: 'https://docs.siliconflow.cn/docs/api/chat-completions-post' },
  { id: 'qwen', label: '通义千问 · 阿里云百炼', name: '通义千问', kind: 'openai', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', exampleModel: 'qwen-plus', help: '百炼大模型通过 OpenAI 兼容协议完成翻译。API Key 必须匹配地域；可填写业务空间 ID 使用专属域名。此预设不接入阿里机器翻译 RPC 服务。', docs: 'https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope' },
  { id: 'deepl', label: 'DeepL API', name: 'DeepL', kind: 'deepl', baseUrl: 'https://api-free.deepl.com/v2', exampleModel: '', help: '此地址用于 DeepL API Free；API Pro 请改为 https://api.deepl.com/v2。无需填写模型。', docs: 'https://developers.deepl.com/api-reference/translate/request-translation' },
  { id: 'volcengine', label: '火山引擎 · 机器翻译', name: '火山引擎翻译', kind: 'volcengine', baseUrl: TRANSLATION_NATIVE_URLS.volcengine, exampleModel: '', help: '火山引擎文本翻译。每月前 200 万字符的免费层以 2026-10 的公开说明为准，可能变化。需要 AccessKey，不是大模型 Key。', docs: 'https://docs.volcengine.com/docs/machine-translation/text-translation-api' },
  { id: 'aliyun', label: '阿里云 · 机器翻译', name: '阿里云机器翻译', kind: 'aliyun', baseUrl: TRANSLATION_NATIVE_URLS.aliyun, exampleModel: '', help: '阿里云机器翻译通用版，不是百炼通义千问。通用版约 100 万字符/月的说明核对于 2026-10，额度用完后可能按量计费。', docs: 'https://help.aliyun.com/zh/machine-translation/developer-reference/api-reference-machine-translation-universal-version-call-guide' },
  { id: 'libretranslate', label: 'LibreTranslate · 自托管', name: 'LibreTranslate', kind: 'libretranslate', baseUrl: 'http://127.0.0.1:5000', exampleModel: '', help: '填写自己的 LibreTranslate 实例地址。示例为本机服务；远程服务需 HTTPS，密钥按实例要求填写。', docs: 'https://docs.libretranslate.com/guides/api_usage/' },
];
export function inferProviderPreset(provider: Provider): ProviderPresetId {
  if (provider.kind === 'system' || provider.kind === 'offline') return provider.kind;
  if (isNativeTranslation(provider.kind)) return provider.kind;
  if (provider.kind === 'deepl' || provider.kind === 'libretranslate') return provider.kind;
  let host = ''; try { host = new URL(provider.baseUrl).hostname; } catch { return 'openai'; }
  if (host === 'api.minimax.cn') return 'minimax';
  if (host === 'api.deepseek.com') return 'deepseek';
  if (host === 'open.bigmodel.cn') return 'zhipu';
  if (host === 'api.siliconflow.cn') return 'siliconflow';
  if (['dashscope.aliyuncs.com', 'dashscope-intl.aliyuncs.com'].includes(host) || host.endsWith('.maas.aliyuncs.com')) return 'qwen';
  return 'openai';
}
export function qwenBaseUrl(region: QwenRegion, workspaceId = ''): string {
  const workspace = workspaceId.trim();
  if (workspace && !/^[A-Za-z0-9_-]+$/.test(workspace)) throw new Error('业务空间 ID 只允许字母、数字、短横线和下划线。');
  if (workspace) return `https://${workspace}.${region === 'singapore' ? 'ap-southeast-1' : 'cn-beijing'}.maas.aliyuncs.com/compatible-mode/v1`;
  return region === 'singapore' ? 'https://dashscope-intl.aliyuncs.com/compatible-mode/v1' : 'https://dashscope.aliyuncs.com/compatible-mode/v1';
}
export function qwenSettingsFromUrl(baseUrl: string): { region: QwenRegion; workspaceId: string } {
  let host = ''; try { host = new URL(baseUrl).hostname; } catch { /* Retain defaults for editable URLs. */ }
  return { region: host.includes('ap-southeast-1') || host === 'dashscope-intl.aliyuncs.com' ? 'singapore' : 'beijing', workspaceId: host.endsWith('.maas.aliyuncs.com') ? host.split('.')[0] : '' };
}
