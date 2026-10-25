import type { Provider, ProviderKind } from './types';

export type ProviderPresetId = 'system' | 'openai' | 'minimax' | 'deepseek' | 'zhipu' | 'siliconflow' | 'qwen' | 'deepl' | 'libretranslate';
export type QwenRegion = 'beijing' | 'singapore';
export interface ProviderPreset {
  id: ProviderPresetId; label: string; name: string; kind: ProviderKind; baseUrl: string; exampleModel: string; help: string; docs: string;
}
// Endpoints verified against the linked vendor documentation on 2026-10-24 (MiniMax: 2026-10-25).
// Model IDs are editable examples, not a statement that a model is newest or available to every account.
export const PROVIDER_PRESETS: readonly ProviderPreset[] = [
  { id: 'system', label: '系统翻译 · 无需 API Key', name: '系统翻译', kind: 'system', baseUrl: '', exampleModel: '', help: '使用当前系统公开提供的翻译能力，无需 API Key。macOS 26 及以上支持；首次可能需要在设置中准备语言包。其他系统的实际可用性以检查结果为准。', docs: 'https://developer.apple.com/documentation/translation/translationsession/init(installedsource:target:)' },
  { id: 'openai', label: 'OpenAI / 自定义兼容接口', name: 'OpenAI 兼容服务', kind: 'openai', baseUrl: 'https://api.openai.com/v1', exampleModel: 'gpt-4o-mini', help: 'OpenAI Chat Completions 兼容协议。可改为你自己的兼容服务地址与模型。', docs: 'https://developers.openai.com/api/reference/overview' },
  { id: 'minimax', label: 'MiniMax · 中国站', name: 'MiniMax', kind: 'openai', baseUrl: 'https://api.minimax.cn/v1', exampleModel: 'MiniMax-M3.1-Flash', help: 'MiniMax 中国站接口，请使用对应地域和账号的 Key；订阅 Key 使用套餐额度。模型可修改，M3.1 Flash 默认深度思考可能增加耗时。', docs: 'https://platform.minimax.cn/docs/api-reference/text-openai-api' },
  { id: 'deepseek', label: 'DeepSeek', name: 'DeepSeek', kind: 'openai', baseUrl: 'https://api.deepseek.com', exampleModel: 'deepseek-flash', help: 'DeepSeek 官方 OpenAI 兼容接口，填写 DeepSeek 平台 API Key。模型名称可修改。', docs: 'https://api-docs.deepseek.com/' },
  { id: 'zhipu', label: '智谱 · BigModel', name: '智谱', kind: 'openai', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', exampleModel: 'glm-5.3', help: '智谱开放平台标准 API。请使用对应平台的 API Key 和已开通模型；Coding Plan 配额与端点可能不同。', docs: 'https://docs.bigmodel.cn/cn/guide/develop/openai/introduction' },
  { id: 'siliconflow', label: '硅基流动 · SiliconFlow', name: '硅基流动', kind: 'openai', baseUrl: 'https://api.siliconflow.cn/v1', exampleModel: 'deepseek-ai/DeepSeek-V4-Flash', help: '硅基流动中国站接口。模型必须填写完整 ID，并以你的账号实际可用列表为准。', docs: 'https://docs.siliconflow.cn/docs/api/chat-completions-post' },
  { id: 'qwen', label: '通义千问 · 阿里云百炼', name: '通义千问', kind: 'openai', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', exampleModel: 'qwen-plus', help: '百炼大模型通过 OpenAI 兼容协议完成翻译。API Key 必须匹配地域；可填写业务空间 ID 使用专属域名。此预设不接入阿里机器翻译 RPC 服务。', docs: 'https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope' },
  { id: 'deepl', label: 'DeepL API', name: 'DeepL', kind: 'deepl', baseUrl: 'https://api-free.deepl.com/v2', exampleModel: '', help: '此地址用于 DeepL API Free；API Pro 请改为 https://api.deepl.com/v2。无需填写模型。', docs: 'https://developers.deepl.com/api-reference/translate/request-translation' },
  { id: 'libretranslate', label: 'LibreTranslate · 自托管', name: 'LibreTranslate', kind: 'libretranslate', baseUrl: 'http://127.0.0.1:5000', exampleModel: '', help: '填写自己的 LibreTranslate 实例地址。示例为本机服务；远程服务需 HTTPS，密钥按实例要求填写。', docs: 'https://docs.libretranslate.com/guides/api_usage/' },
];
export function inferProviderPreset(provider: Provider): ProviderPresetId {
  if (provider.kind === 'system') return 'system';
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
