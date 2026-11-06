export function useKitchenDemand(activeOrders) {
  if (!activeOrders || activeOrders.length === 0) {
    return { level: 'NORMAL', message: 'Fila Vazia', color: 'bg-gray-500', pendingBurgers: 0 };
  }

  let totalBurgers = 0;
  
  activeOrders.forEach(order => {
    order.items?.forEach(item => {
      if (item.name.toLowerCase().includes('burger') || item.name.toLowerCase().includes('dogão')) {
        totalBurgers += item.quantity;
      }
    });
  });

  const WARNING_THRESHOLD = 8;
  const CRITICAL_THRESHOLD = 15;

  if (totalBurgers >= CRITICAL_THRESHOLD) {
    return {
      level: 'CRITICAL',
      message: `Sobrecarga: ${totalBurgers} na chapa!`,
      color: 'bg-red-500',
      pendingBurgers: totalBurgers
    };
  } else if (totalBurgers >= WARNING_THRESHOLD) {
    return {
      level: 'WARNING',
      message: `Atenção: ${totalBurgers} na fila`,
      color: 'bg-yellow-500',
      pendingBurgers: totalBurgers
    };
  } else {
    return {
      level: 'NORMAL',
      message: 'Fluxo Controlado',
      color: 'bg-green-500',
      pendingBurgers: totalBurgers
    };
  }
}