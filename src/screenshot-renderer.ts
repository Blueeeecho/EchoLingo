import { mosaicPixels, wrapText, operationBounds, screenshotTextFont, type EditOperation, type Size, type Point, type StrokeOperation } from './screenshot-model';
const context = (canvas: HTMLCanvasElement) => {
  const ctx = canvas.getContext('2d', { willReadFrequently: true });
  if (!ctx) throw new Error('无法创建图片画布，请重新打开截图窗口。');
  return ctx;
};
function drawBadge(ctx: CanvasRenderingContext2D, point: Point, size: number, number: number, color: string): void {
  ctx.fillStyle = color; ctx.beginPath(); ctx.arc(point.x, point.y, size / 2, 0, Math.PI * 2); ctx.fill();
  // Legible labels on both very dark and very light chosen colors.
  const rgb = [1, 3, 5].map(i => parseInt(color.slice(i, i + 2), 16));
  ctx.fillStyle = rgb[0] * .299 + rgb[1] * .587 + rgb[2] * .114 > 160 ? '#111111' : '#ffffff';
  ctx.font = `600 ${screenshotTextFont(size * (number > 999 ? .32 : number > 99 ? .42 : .55))}`;
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle'; ctx.fillText(String(number), point.x, point.y);
}
function strokePath(ctx: CanvasRenderingContext2D, points: readonly Point[], width: number): void {
  ctx.lineWidth = width; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  if (points.length === 1) { ctx.beginPath(); ctx.arc(points[0].x, points[0].y, width / 2, 0, Math.PI * 2); ctx.fill(); return; }
  ctx.beginPath(); ctx.moveTo(points[0].x, points[0].y); for (const point of points.slice(1)) ctx.lineTo(point.x, point.y); ctx.stroke();
}
function drawStroke(ctx: CanvasRenderingContext2D, operation: StrokeOperation, width: number, height: number): void {
  // Erasure is isolated to this transparent annotation surface. Never use
  // destination-out on the source image or any mosaic/opaque privacy mask.
  const bounds = operationBounds(operation), x = Math.max(0, Math.floor(bounds.x)), y = Math.max(0, Math.floor(bounds.y));
  const right = Math.min(width, Math.ceil(bounds.x + bounds.width)), bottom = Math.min(height, Math.ceil(bounds.y + bounds.height));
  if (right <= x || bottom <= y) return;
  const layer = document.createElement('canvas'); layer.width = right - x; layer.height = bottom - y;
  const paint = context(layer); paint.translate(-x, -y); paint.fillStyle = operation.color; paint.strokeStyle = operation.color;
  strokePath(paint, operation.points, operation.width);
  paint.globalCompositeOperation = 'destination-out';
  for (const erasure of operation.erasures ?? []) strokePath(paint, erasure.points, erasure.width);
  ctx.save(); ctx.globalAlpha = operation.kind === 'highlight' ? .3 : 1; ctx.drawImage(layer, x, y); ctx.restore();
  layer.width = layer.height = 1;
}
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
    if (operation.kind === 'pen' || operation.kind === 'highlight') {
      drawStroke(ctx, operation, canvas.width, canvas.height);
    } else if (operation.kind === 'mosaic') {
      const { x, y, width, height } = operation.rect, pixels = ctx.getImageData(x, y, width, height);
      mosaicPixels(pixels.data, width, height, operation.blockSize); ctx.putImageData(pixels, x, y);
    } else {
      ctx.strokeStyle = operation.color; ctx.fillStyle = operation.color;
      if (operation.kind === 'ellipse') {
        const { x, y, width, height } = operation.rect; ctx.lineWidth = operation.width;
        ctx.beginPath(); ctx.ellipse(x + width / 2, y + height / 2, Math.max(0, (width - operation.width) / 2), Math.max(0, (height - operation.width) / 2), 0, 0, Math.PI * 2); ctx.stroke();
      } else if (operation.kind === 'rectangle') {
        const { x, y, width, height } = operation.rect;
        if (operation.solid) ctx.fillRect(x, y, width, height);
        else { ctx.lineWidth = operation.width; const inset = Math.min(width / 2, height / 2, operation.width / 2);
          ctx.strokeRect(x + inset, y + inset, Math.max(0, width - 2 * inset), Math.max(0, height - 2 * inset)); }
      } else if (operation.kind === 'arrow' || operation.kind === 'numbered-arrow') {
        const { start, end, width } = operation, angle = Math.atan2(end.y - start.y, end.x - start.x), head = Math.max(10, width * 4);
        ctx.lineWidth = width; ctx.lineCap = 'round'; ctx.lineJoin = 'round';
        ctx.beginPath(); ctx.moveTo(start.x, start.y); ctx.lineTo(end.x, end.y); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(end.x, end.y);
        ctx.lineTo(end.x - head * Math.cos(angle - Math.PI / 6), end.y - head * Math.sin(angle - Math.PI / 6));
        ctx.lineTo(end.x - head * Math.cos(angle + Math.PI / 6), end.y - head * Math.sin(angle + Math.PI / 6)); ctx.closePath(); ctx.fill();
        if (operation.kind === 'numbered-arrow') drawBadge(ctx, operation.start, operation.size, operation.number, operation.color);
      } else if (operation.kind === 'number') {
        drawBadge(ctx, operation.point, operation.size, operation.number, operation.color);
      } else if (operation.kind === 'text') {
        ctx.font = screenshotTextFont(operation.size);
        if (operation.background) {
          const bounds = operationBounds(operation, text => ctx.measureText(text).width);
          ctx.fillStyle = operation.background; ctx.fillRect(bounds.x, bounds.y, bounds.width, bounds.height); ctx.fillStyle = operation.color;
        }
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
