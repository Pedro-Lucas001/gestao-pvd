import { useState, useEffect } from 'react';

export function useConnection() {
  const [isOnline, setIsOnline] = useState(navigator.onLine);

  useEffect(() => {
    const handleOnline = () => {
      setIsOnline(true);
      // Aqui disparamos a função para sincronizar os pedidos que ficaram retidos no IndexedDB
      window.dispatchEvent(new CustomEvent('sync-offline-orders'));
    };
    
    const handleOffline = () => setIsOnline(false);

    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);

    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  return { isOnline };
}