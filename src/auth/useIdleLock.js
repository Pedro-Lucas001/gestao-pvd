import { useEffect } from "react";

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

export function useIdleLock(enabled, onLock, onActivity) {
  useEffect(() => {
    if (!enabled) return;

    let lastWall = Date.now();
    let lastMonotonic = performance.now();
    let didLock = false;

    function checkExpiration() {
      if (didLock) return true;
      if (!expiredActivity(lastWall, lastMonotonic, Date.now(), performance.now())) {
        return false;
      }
      didLock = true;
      onLock();
      return true;
    }

    function recordActivity(event) {
      if (!event.isTrusted) return;
      // Uma interação após o prazo bloqueia em vez de renovar a sessão.
      if (checkExpiration()) return;
      lastWall = Date.now();
      lastMonotonic = performance.now();
      onActivity?.();
    }

    function checkVisibility() {
      if (document.visibilityState === "visible") checkExpiration();
    }

    const events = ["pointerdown", "pointermove", "keydown", "wheel", "touchstart"];
    const listenerOptions = { capture: true, passive: true };
    for (const event of events) {
      window.addEventListener(event, recordActivity, listenerOptions);
    }
    window.addEventListener("focus", checkExpiration);
    window.addEventListener("pageshow", checkExpiration);
    document.addEventListener("visibilitychange", checkVisibility);
    const timer = setInterval(checkExpiration, 1000);

    return () => {
      clearInterval(timer);
      for (const event of events) {
        window.removeEventListener(event, recordActivity, listenerOptions);
      }
      window.removeEventListener("focus", checkExpiration);
      window.removeEventListener("pageshow", checkExpiration);
      document.removeEventListener("visibilitychange", checkVisibility);
    };
  }, [enabled, onLock, onActivity]);
}
