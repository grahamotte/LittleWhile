import { loopHeight, loopPath } from "../../src/lib/loop";
import { describe, expect, test } from "vitest";

describe("loopPath", () => {
  test("starts on the baseline", () => {
    expect(loopPath(1).startsWith("M0 80 C")).toBe(true);
  });

  test("draws four curves per loop", () => {
    expect(loopPath(1).match(/C/g)).toHaveLength(4);
    expect(loopPath(5).match(/C/g)).toHaveLength(20);
  });

  test("ends on the baseline after the last loop", () => {
    expect(loopPath(1).endsWith("100 80")).toBe(true);
    expect(loopPath(5).endsWith("500 80")).toBe(true);
  });

  test("joins loops end to start", () => {
    const path = loopPath(2);
    expect(path).toContain("100 80 C122 80 140 70 154 54");
  });

  test("scales horizontally with the period", () => {
    expect(loopPath(2, 50).endsWith("100 80")).toBe(true);
    expect(loopPath(1, 50)).toContain("27 54");
  });

  test("keeps every point inside the drawing height", () => {
    const ys = loopPath(3)
      .replace(/[MC]/g, "")
      .trim()
      .split(/\s+/)
      .filter((_, index) => index % 2 === 1)
      .map(Number);
    expect(Math.min(...ys)).toBeGreaterThanOrEqual(0);
    expect(Math.max(...ys)).toBeLessThanOrEqual(loopHeight);
  });

  test("draws nothing past the start without loops", () => {
    expect(loopPath(0)).toBe("M0 80");
  });
});
