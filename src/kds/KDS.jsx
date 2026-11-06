import { useState } from 'react';
import { useConnection } from '../components/useConnection';
import { useKitchenDemand } from './useKitchenDemand';
import OrderTicketCard from './OrderTicketCard';

export default function KDS() {
  const [activeOrders] = useState([
    {
      id: '1a2b',
      customer_name: 'João Silva',
      order_type: 'balcao',
      items: [
        { 
          quantity: 2, 
          name: 'Mega Planeta Burger',
          modifiers: [
            { type: 'remove', name: 'Cebola' },
            { type: 'add', name: 'Bacon' }
          ]
        }
      ]
    }
  ]);
  
  const { isOnline } = useConnection();
  const demand = useKitchenDemand(activeOrders); // Chamada correta do hook

  return (
    <div className="min-h-screen bg-dark-900 flex flex-col font-sans">
      <header className="bg-dark-800 border-b border-dark-700 p-4 flex justify-between items-center shadow-glass z-10">
        <div className="flex items-center gap-4">
          <h1 className="text-2xl font-bold text-white tracking-tight">KDS <span className="text-brasa-500">Produção</span></h1>
          <div className="h-6 w-px bg-dark-700"></div>
          <span className="text-gray-400 font-medium">{activeOrders.length} Pedidos na Fila</span>
        </div>
        
        <div className="flex items-center gap-3">
          {!isOnline && (
            <div className="flex items-center gap-2 bg-red-900/20 border border-red-500/50 px-4 py-2 rounded-lg">
              <div className="w-3 h-3 rounded-full bg-red-500 animate-pulse"></div>
              <span className="text-sm font-bold text-red-400 uppercase tracking-wider">Modo Offline</span>
            </div>
          )}

          <div className="flex items-center gap-3 bg-dark-900 px-4 py-2 rounded-lg border border-dark-700">
            <div className={`w-3 h-3 rounded-full animate-pulse ${demand.color}`}></div>
            <span className="text-sm font-bold text-gray-300">{demand.message}</span>
          </div>
        </div>
      </header>

      <main className="flex-1 p-6 overflow-x-auto">
        <div className="grid grid-cols-1 md:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 gap-4 items-start">
          {activeOrders.map(order => (
            <OrderTicketCard key={order.id} order={order} />
          ))}
        </div>
      </main>
    </div>
  );
}