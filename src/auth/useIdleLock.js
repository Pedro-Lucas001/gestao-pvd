import { useState, useEffect } from 'react';

export function useIdleLock(timeoutMs = 300000) { // 5 minutos por defeito
  const [isLocked, setIsLocked] = useState(false);

  useEffect(() => {
    let timeout;
    
    const resetTimer = () => {
      if (!isLocked) {
        clearTimeout(timeout);
        timeout = setTimeout(() => setIsLocked(true), timeoutMs);
      }
    };

    // Ouve qualquer interação do utilizador
    const events = ['mousemove', 'mousedown', 'keypress', 'touchstart', 'scroll'];
    events.forEach(event => window.addEventListener(event, resetTimer));
    
    resetTimer();

    return () => {
      clearTimeout(timeout);
      events.forEach(event => window.removeEventListener(event, resetTimer));
    };
  }, [isLocked, timeoutMs]);

  const unlock = () => setIsLocked(false);

  return { isLocked, unlock, setIsLocked };
}