import { describe, expect, it } from 'vitest';
import { FREE_COMBOS, combosFor } from '../src/free-combos';
import { tx } from '../src/ui-text';

describe('free service combinations', () => {
  it('offers the approved mainland and overseas sets without Tencent text translation', () => {
    expect(combosFor('cn').map((combo) => combo.id)).toEqual([
      'cn-siliconflow-baidu-ocr', 'cn-baidu-tencent-ocr', 'cn-zhipu',
    ]);
    expect(combosFor('overseas').map((combo) => combo.id)).toEqual([
      'os-azure-google', 'os-deepl-azure-vision',
    ]);
    const kinds = FREE_COMBOS.flatMap((combo) => combo.pieces.map((piece) => piece.kind));
    expect(kinds).not.toContain('tencent-mt');
    expect(JSON.stringify(FREE_COMBOS)).not.toMatch(/gemini|generativelanguage/i);
    expect(kinds.filter((kind) => kind === 'tencent')).toEqual(['tencent']);
  });

  it('labels quotas as checked in 2026-10 and never promises permanent free use', () => {
    const text = FREE_COMBOS.flatMap((combo) => [combo.detailZh, combo.detailEn, ...combo.pieces.flatMap((piece) => [piece.quotaZh, piece.quotaEn])]).join('\n');
    expect(text).toContain('2026-10');
    expect(text).toContain('Checked in 2026-10');
    expect(text).not.toMatch(/永久免费|permanently free/i);
    expect(text.toLowerCase()).not.toContain('helloworld');
  });

  it('follows the active UI language', () => {
    expect(tx('中文', 'English', 'zh')).toBe('中文');
    expect(tx('中文', 'English', 'en')).toBe('English');
  });
});
