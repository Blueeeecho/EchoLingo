import { mosaicPixels, wrapText, type EditOperation, type Size } from './screenshot-model';
const context = (canvas: HTMLCanvasElement) => {
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) throw new Error('无法创建图片画布，请重新打开截图窗口。');
  return ctx;
};
/** Each render starts with the immutable decoded source. Crops change actual
 * canvas dimensions, not a viewport or exported hidden layer. */
export function renderScreenshot(canvas: HTMLCanvasElement, original: CanvasImageSource, size: Size, operations: readonly EditOperation[]): void {
  canvas.width = size.width; canvas.height = size.height;
  let ctx = context(canvas); ctx.drawImage(original, 0, 0, size.width, size.height);
  for (const operation of operations) {
    if (operation.kind === 'crop') {
      const { x, y, width, height } = operation.rect;
      const cropped = ctx.getImageData(x, y, width, height);
      canvas.width = width; canvas.height = height; ctx = context(canvas); ctx.putImageData(cropped, 0, 0); continue;
    }
    ctx.save();
    if (operation.kind === 'mosaic') {
      const { x, y, width, height } = operation.rect, pixels = ctx.getImageData(x, y, width, height);
      mosaicPixels(pixels.data, width, height, operation.blockSize); ctx.putImageData(pixels, x, y);
    } else {
      ctx.strokeStyle = operation.color; ctx.fillStyle = operation.color;
      if (operation.kind === 'rectangle') {
        const { x, y, width, height } = operation.rect;
        if (operation.solid) ctx.fillRect(x, y, width, height);
        else { ctx.lineWidth = operation.width; const inset = Math.min(width / 2, height / 2, operation.width / 2);
          ctx.strokeRect(x + inset, y + inset, Math.max(0, width - 2 * inset), Math.max(0, height - 2 * inset)); }
      } else if (operation.kind === 'arrow') {
        const { start, end, width } = operation, angle = Math.atan2(end.y - start.y, end.x - start.x), head = Math.max(10, width * 4);
        ctx.lineWidth = width; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
        ctx.beginPath(); ctx.moveTo(start.x, start.y); ctx.lineTo(end.x, end.y); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(end.x, end.y);
        ctx.lineTo(end.x - head * Math.cos(angle - Math.PI / 6), end.y - head * Math.sin(angle - Math.PI / 6));
        ctx.lineTo(end.x - head * Math.cos(angle + Math.PI / 6), end.y - head * Math.sin(angle + Math.PI / 6)); ctx.closePath(); ctx.fill();
      } else if (operation.kind === 'text') {
        ctx.font = `${operation.size}px -apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif`;
        ctx.textBaseline = 'top'; const lineHeight = operation.size * 1.35;
        const lines = wrapText(operation.text, operation.maxWidth, text => ctx.measureText(text).width);
        lines.forEach((line, index) => { const y = operation.point.y + index * lineHeight;
          if (y < canvas.height) ctx.fillText(line, operation.point.x, y); });
      }
    }
    ctx.restore();
  }
}
export async function flattenedPng(canvas: HTMLCanvasElement): Promise<string> {
  const blob = await new Promise<Blob>((resolve, reject) => canvas.toBlob(value => value ? resolve(value) : reject(new Error('无法导出 PNG 图片。')), 'image/png'));
  if (blob.size > 32 * 1024 * 1024) throw new Error('导出的 PNG 超过 32 MiB，请裁剪后再保存。');
  return new Promise((resolve, reject) => { const reader = new FileReader(); reader.onerror = () => reject(new Error('无法读取导出的图片。'));
    reader.onload = () => resolve(String(reader.result).split(',')[1]); reader.readAsDataURL(blob); });
}
