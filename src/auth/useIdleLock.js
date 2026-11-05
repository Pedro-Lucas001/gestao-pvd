import { useEffect } from "react";
export const IDLE_LIMIT_MS = 10 * 60 * 1000;
export function expiredActivity(wall, mono, nowWall, nowMono) {
  return nowWall - wall >= IDLE_LIMIT_MS || nowMono - mono >= IDLE_LIMIT_MS;
}
export function useIdleLock(enabled, onLock, onActive) {
  useEffect(() => {
    if (!enabled) return;
    let lastWall = Date.now(),
      lastMono = performance.now(),
      timer;
    const expired = () =>
      expiredActivity(lastWall, lastMono, Date.now(), performance.now());
    const lock = () => {
      clearTimeout(timer);
      onLock();
    };
    const schedule = () => {
      clearTimeout(timer);
      timer = setTimeout(lock, IDLE_LIMIT_MS);
    };
    const input = (event) => {
      if (!event.isTrusted) return;
      if (expired()) {
        lock();
        return;
      }
      lastWall = Date.now();
      lastMono = performance.now();
      schedule();
      onActive();
    };
    const visible = () => {
      if (!document.hidden && expired()) lock();
    };
    const events = [
      "pointerdown",
      "pointermove",
      "keydown",
      "wheel",
      "touchstart",
    ];
    for (const type of events)
      window.addEventListener(type, input, { passive: true });
    document.addEventListener("visibilitychange", visible);
    schedule();
    return () => {
      clearTimeout(timer);
      for (const type of events) window.removeEventListener(type, input);
      document.removeEventListener("visibilitychange", visible);
    };
  }, [enabled, onLock, onActive]);
}
