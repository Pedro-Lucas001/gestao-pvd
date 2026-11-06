import React, { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';
import { useConnection } from '../components/useConnection'; // O nosso sensor de rede
import OrderTicketCard from './OrderTicketCard';

export default function KDS() {
  const [activeOrders, setActiveOrders] = useState([]);
  const { isOnline } = useConnection(); // Captura o estado da rede em tempo real

  // ... (manter o useEffect do Realtime que já fizemos)

  return (
    <div className="min-h-screen bg-dark-900 flex flex-col font-sans">
      <header className="bg-dark-800 border-b border-dark-700 p-4 flex justify-between items-center shadow-glass z-10">
        <div className="flex items-center gap-4">
          <h1 className="text-2xl font-bold text-white tracking-tight">KDS <span className="text-brasa-500">Produção</span></h1>
          <div className="h-6 w-px bg-dark-700"></div>
          <span className="text-gray-400 font-medium">{activeOrders.length} Pedidos na Fila</span>
        </div>
        
        <div className="flex items-center gap-3">
          {/* Alerta Visual de Queda de Rede */}
          {!isOnline && (
            <div className="flex items-center gap-2 bg-red-900/20 border border-red-500/50 px-4 py-2 rounded-lg">
              <div className="w-3 h-3 rounded-full bg-red-500 animate-pulse"></div>
              <span className="text-sm font-bold text-red-400 uppercase tracking-wider">Modo Offline</span>
            </div>
          )}

          {/* Indicador Analítico Adaptativo */}
          <div className="flex items-center gap-3 bg-dark-900 px-4 py-2 rounded-lg border border-dark-700">
            <div className={`w-3 h-3 rounded-full animate-pulse ${isOnline ? 'bg-green-500' : 'bg-yellow-500'}`}></div>
            <span className="text-sm font-bold text-gray-300">
              {isOnline ? 'Chapa Normal' : 'Sincronização Pausada'}
            </span>
          </div>
        </div>
      </header>

      {/* Grid de Tickets ... */}
      <main className="flex-1 p-6 overflow-x-auto">
        <div className="grid grid-cols-1 md:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5 gap-4 items-start">
          {activeOrders.map(order => (
            <OrderTicketCard key={order.id} order={order} />
          ))}
        </div>
        <div className="flex items-center gap-3 bg-dark-900 px-4 py-2 rounded-lg border border-dark-700">
  <div className={`w-3 h-3 rounded-full animate-pulse ${demand.color}`}></div>
  <span className="text-sm font-bold text-gray-300">{demand.message}</span>
</div>
      </main>
    </div>
  );
}