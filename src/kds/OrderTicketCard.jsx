import React from 'react';

export default function OrderTicketCard({ order }) {
  // Define a cor do cabeçalho com base no tipo de pedido e tempo de espera
  const getHeaderColor = (type) => {
    const colors = {
      'balcao': 'bg-brasa-500 text-white',
      'mesa': 'bg-blue-600 text-white',
      'delivery': 'bg-purple-600 text-white'
    };
    return colors[type] || 'bg-dark-700 text-gray-300';
  };

  return (
    <div className="bg-dark-800 rounded-xl border border-dark-700 shadow-glass flex flex-col overflow-hidden">
      {/* Cabeçalho do Pedido */}
      <div className={`px-4 py-3 flex justify-between items-center font-bold ${getHeaderColor(order.order_type)}`}>
        <div className="flex flex-col">
          <span className="text-lg uppercase tracking-wider">
            {order.order_type} {order.table_number ? order.table_number : `#${order.id.slice(0,4)}`}
          </span>
          <span className="text-xs font-medium opacity-80">{order.customer_name}</span>
        </div>
        <div className="text-right">
          <span className="block text-sm">14:32</span>
          <span className="block text-xs opacity-80 animate-pulse">05:45 min</span>
        </div>
      </div>

      {/* Lista de Itens e Motor de Modificadores */}
      <div className="flex-1 p-4 overflow-y-auto space-y-4 bg-dark-900">
        {order.items.map((item, index) => (
          <div key={index} className="border-b border-dark-700 pb-3 last:border-0 last:pb-0">
            <div className="flex items-start gap-3">
              <span className="bg-dark-700 text-white px-2 py-1 rounded text-sm font-bold border border-dark-700">
                {item.quantity}x
              </span>
              <div className="flex-1">
                <h3 className="text-gray-100 font-bold text-lg">{item.name}</h3>
                
                {/* Lógica de Desmembramento Visual */}
                {item.modifiers && item.modifiers.length > 0 && (
                  <ul className="mt-2 space-y-1 bg-dark-800 p-2 rounded-md border border-dark-700">
                    {item.modifiers.map((mod, i) => (
                      <li key={i} className="text-sm font-bold tracking-wide">
                        {mod.type === 'remove' ? (
                          <span className="text-red-500 animate-pulse flex items-center gap-1">
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M20 12H4"></path></svg>
                            SEM {mod.name.toUpperCase()}
                          </span>
                        ) : (
                          <span className="text-green-400 flex items-center gap-1">
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4v16m8-8H4"></path></svg>
                            EXTRA: {mod.name.toUpperCase()}
                          </span>
                        )}
                      </li>
                    ))}
                  </ul>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Ações da Cozinha */}
      <div className="p-3 bg-dark-800 border-t border-dark-700 grid grid-cols-2 gap-2">
        <button className="bg-dark-700 hover:bg-dark-900 text-white py-2 rounded-lg font-semibold transition-colors border border-dark-700">
          Imprimir
        </button>
        <button className="bg-brasa-500 hover:bg-brasa-600 text-white py-2 rounded-lg font-bold shadow-brasa-glow transition-all uppercase">
          Pronto
        </button>
      </div>
    </div>
  );
}