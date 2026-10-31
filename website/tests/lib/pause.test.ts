import { pauseState, pauseWindow } from "../../src/lib/pause";
import { describe, expect, test } from "vitest";

describe("pauseState", () => {
  test("starts with the whole minute left", () => {
    expect(pauseState(0)).toEqual({ seconds: 60, fraction: 1 });
  });

  test("counts down whole seconds, rounding up", () => {
    expect(pauseState(0.2).seconds).toBe(60);
    expect(pauseState(1).seconds).toBe(59);
    expect(pauseState(59.5).seconds).toBe(1);
  });

  test("shrinks the wedge with the time left", () => {
    expect(pauseState(15).fraction).toBe(0.75);
    expect(pauseState(45).fraction).toBe(0.25);
  });

  test("starts over after the window", () => {
    expect(pauseState(pauseWindow)).toEqual({ seconds: 60, fraction: 1 });
    expect(pauseState(pauseWindow + 30)).toEqual(pauseState(30));
  });

  test("handles a shorter window", () => {
    expect(pauseState(5, 10)).toEqual({ seconds: 5, fraction: 0.5 });
  });

  test("wraps negative elapsed time into the window", () => {
    expect(pauseState(-15)).toEqual(pauseState(45));
  });
});
