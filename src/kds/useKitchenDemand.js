import { useState, useEffect } from 'react';

export function useKitchenDemand(activeOrders) {
  const [demandStatus, setDemandStatus] = useState({
    level: 'NORMAL', // NORMAL, WARNING, CRITICAL
    message: 'Chapa Normal',
    color: 'bg-green-500',
    pendingBurgers: 0
  });

  useEffect(() => {
    if (!activeOrders || activeOrders.length === 0) {
      setDemandStatus({ level: 'NORMAL', message: 'Fila Vazia', color: 'bg-gray-500', pendingBurgers: 0 });
      return;
    }

    // Algoritmo Preditivo: Conta a quantidade de itens complexos (ex: hambúrgueres)
    let totalBurgers = 0;
    
    activeOrders.forEach(order => {
      order.items?.forEach(item => {
        // Se o nome do produto incluir "Burger", "Dogão" ou for uma categoria de chapa
        if (item.name.toLowerCase().includes('burger') || item.name.toLowerCase().includes('dogão')) {
          totalBurgers += item.quantity;
        }
      });
    });

    // Define os limites operacionais da lanchonete (ajustável)
    const WARNING_THRESHOLD = 8;  // A partir de 8 hambúrgueres na fila, a chapa começa a apertar
    const CRITICAL_THRESHOLD = 15; // 15+ significa que o tempo de espera vai estourar

    if (totalBurgers >= CRITICAL_THRESHOLD) {
      setDemandStatus({
        level: 'CRITICAL',
        message: `Sobrecarga: ${totalBurgers} na chapa!`,
        color: 'bg-red-500',
        pendingBurgers: totalBurgers
      });
    } else if (totalBurgers >= WARNING_THRESHOLD) {
      setDemandStatus({
        level: 'WARNING',
        message: `Atenção: ${totalBurgers} na fila`,
        color: 'bg-yellow-500',
        pendingBurgers: totalBurgers
      });
    } else {
      setDemandStatus({
        level: 'NORMAL',
        message: 'Fluxo Controlado',
        color: 'bg-green-500',
        pendingBurgers: totalBurgers
      });
    }

  }, [activeOrders]);

  return demandStatus;
}