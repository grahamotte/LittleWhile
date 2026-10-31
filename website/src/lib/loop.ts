const curves = [
  [-28, 80, -10, 70, 4, 54],
  [24, 32, 24, 6, 0, 6],
  [-24, 6, -24, 32, -4, 54],
  [10, 70, 28, 80, 50, 80],
];

export const loopHeight = 86;

export function loopPath(count: number, period = 100): string {
  const scale = period / 100;
  const point = (x: number, y: number) => `${round(x * scale)} ${y}`;
  const loops = Array.from({ length: count }, (_, index) => {
    const center = 50 + index * 100;
    return curves
      .map(([c1x, c1y, c2x, c2y, x, y]) => `C${point(center + c1x, c1y)} ${point(center + c2x, c2y)} ${point(center + x, y)}`)
      .join(" ");
  });
  return ["M0 80", ...loops].join(" ");
}

function round(value: number): number {
  return Math.round(value * 100) / 100;
}
