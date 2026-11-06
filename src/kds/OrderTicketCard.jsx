export default function OrderTicketCard({ order }) {
  return (
    <div className="bg-dark-800 border border-dark-700 rounded-2xl p-4 flex flex-col gap-4 shadow-glass w-72">
      <div className="flex justify-between items-center border-b border-dark-700 pb-3">
        <span className="font-bold text-white text-lg">#{order.id.slice(0, 4).toUpperCase()}</span>
        <span className="bg-brasa-500/10 text-brasa-500 border border-brasa-500/30 text-xs px-2 py-1 rounded-md font-bold uppercase">
          {order.order_type || 'Balcão'}
        </span>
      </div>

      <div className="flex flex-col gap-2">
        <p className="text-gray-400 text-xs font-bold uppercase tracking-wider">Cliente: {order.customer_name || 'Balcão'}</p>
        <div className="space-y-2 mt-2">
          {order.items?.map((item, idx) => (
            <div key={idx} className="bg-dark-900 p-3 rounded-xl border border-dark-700">
              <div className="flex justify-between font-bold text-white">
                <span>{item.quantity}x {item.name}</span>
              </div>
              {item.modifiers && item.modifiers.length > 0 && (
                <div className="mt-1 text-xs text-gray-400">
                  {item.modifiers.map((mod, mIdx) => (
                    <span key={mIdx} className={`block ${mod.type === 'remove' ? 'text-red-400' : 'text-green-400'}`}>
                      {mod.type === 'remove' ? '- Sem ' : '+ '} {mod.name}
                    </span>
                  ))}
                </div>
              )}
            </div>
          ))}
        </div>
      </div>

      <button className="mt-2 w-full bg-dark-700 hover:bg-brasa-500 text-white font-bold py-3 rounded-xl transition-colors uppercase tracking-wider text-sm">
        Avançar Estado
      </button>
    </div>
  );
}