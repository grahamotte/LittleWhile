export const pauseWindow = 60;

export function pauseState(elapsed: number, window = pauseWindow): { seconds: number; fraction: number } {
  const remaining = window - (((elapsed % window) + window) % window);
  return {
    seconds: Math.ceil(remaining),
    fraction: Math.min(1, Math.max(0, remaining / window)),
  };
}
