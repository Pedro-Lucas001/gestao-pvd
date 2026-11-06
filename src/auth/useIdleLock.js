export const IDLE_LIMIT_MS = 10 * 60 * 1000;

export function expiredActivity(
  lastWall,
  lastMonotonic,
  nowWall,
  nowMonotonic,
) {
  const wallElapsed = nowWall - lastWall;
  const monotonicElapsed = nowMonotonic - lastMonotonic;

  return Math.max(wallElapsed, monotonicElapsed) >= IDLE_LIMIT_MS;
}