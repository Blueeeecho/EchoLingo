const DAY_MS = 24 * 60 * 60 * 1000;

export interface EngineHintState { dismissed: boolean; shownAt: number }

export function shouldShowFirstRun(state: EngineHintState): boolean {
  return !state.dismissed && state.shownAt <= 0;
}

export function shouldShowSoftHint(state: EngineHintState, now: number): boolean {
  if (state.dismissed) return false;
  if (!Number.isFinite(now)) return false;
  return state.shownAt <= 0 || now - state.shownAt >= DAY_MS;
}

export function isWeakEngineSignal(text: string): boolean {
  const value = text.trim();
  if (!value || /^(?:CANCELLED|PERMISSION|NO_SELECTION|SELECTION_EMPTY):/i.test(value) || /^未取得选区/.test(value)) return false;
  return /没有识别|翻译失败|NO_TEXT:|OCR_|识别失败|服务返回错误/.test(value);
}

export function engineLimitCopy(kinds: string[], localOcr: boolean): { title: string; detail: string } {
  const localTranslation = kinds.length === 0 || kinds.every((kind) => kind === 'offline' || kind === 'system');
  const title = localTranslation ? '当前是本机翻译' : '当前有云端翻译服务';
  const translation = localTranslation
    ? '内置或系统翻译适合短句。长文、术语或其它语言可以在设置里另加服务；只有你启用云端服务后，原文才会发给该服务商。'
    : '已启用的云端翻译会收到你提交的原文。密钥留在系统凭据库，不会写入历史。';
  const ocr = localOcr
    ? '截图默认识别用本机 OCR，复杂版面或很小的字可能不准。改用云端 OCR 时，选区图片会发给该服务商。'
    : '当前截图识别会把选区图片发给所选 OCR 服务商。';
  return { title, detail: `${translation}${ocr}` };
}
