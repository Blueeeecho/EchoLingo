import { describe, it, expect } from 'vitest';
import { draftAnnotation, type DraftStyle } from './screenshot-draft';
import { ScreenshotDocument } from './screenshot-model';
const style: DraftStyle = { color:'#ff0000', width:8, fontSize:24, blockSize:8, ellipse:false, numberThreshold:4 };
const size = { width:200, height:100 }, start = {x:20,y:20};
describe('final-style annotation draft', () => {
  it('uses the chosen style for rectangle, ellipse, arrow and opaque mask', () => {
    for (const [tool, kind] of [['rectangle','rectangle'],['arrow','arrow'],['solid','rectangle']] as const) {
      const op = draftAnnotation(tool,start,{x:80,y:60},size,style,1)!;
      expect(op.kind).toBe(kind); expect(op).toMatchObject({color:'#ff0000',width:8});
    }
    expect(draftAnnotation('rectangle',start,{x:80,y:60},size,{...style,ellipse:true},1)?.kind).toBe('ellipse');
    expect(draftAnnotation('solid',start,{x:80,y:60},size,style,1)).toMatchObject({solid:true});
  });
  it('clicks produce one badge; held drags produce one atomic numbered arrow without reserving numbers', () => {
    const model = new ScreenshotDocument(size);
    const badge = draftAnnotation('number',start,{x:22,y:20},size,style,model.nextNumber)!;
    expect(badge.kind).toBe('number');
    for (let x=30; x<90; x++) expect(draftAnnotation('number',start,{x,y:60},size,style,model.nextNumber)).toMatchObject({kind:'numbered-arrow',number:1,start});
    expect(model.operations).toHaveLength(0); expect(model.nextNumber).toBe(1);
    const arrow = draftAnnotation('number',start,{x:90,y:60},size,style,model.nextNumber)!;
    model.append(arrow); expect(model.operations).toHaveLength(1); expect(model.nextNumber).toBe(2);
    model.undo(); expect(model.operations).toHaveLength(0); expect(model.nextNumber).toBe(1);
    model.redo(); expect(model.operations[0]).toEqual(arrow);
  });
  it('keeps click threshold display-scaled and does not commit crop while previewing', () => {
    expect(draftAnnotation('number',start,{x:27,y:20},size,{...style,numberThreshold:8},1)?.kind).toBe('number');
    expect(draftAnnotation('number',start,{x:28,y:20},size,{...style,numberThreshold:8},1)?.kind).toBe('numbered-arrow');
    expect(draftAnnotation('crop',start,{x:80,y:60},size,style,1)).toBeNull();
  });
});
