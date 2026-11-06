import { useState } from 'react';
import { useConnection } from '../components/useConnection';
import { saveOrderOffline } from '../lib/network';

export default function PdvTemplate() {
  const [cart, setCart] = useState([]);
  const [customerPhone, setCustomerPhone] = useState('');
  const { isOnline } = useConnection();

  const handleCheckout = async () => {
    const orderPayload = { 
      items: cart, 
      total: 37.90,
      customer_phone: customerPhone || null 
    };

    if (isOnline) {
      console.log('Enviado para o banco de dados:', orderPayload);
      alert('Pedido enviado para o KDS!');
    } else {
      await saveOrderOffline(orderPayload);
      alert('Sem rede! Pedido guardado na fila local e será enviado automaticamente.');
    }
    
    setCart([]);
    setCustomerPhone('');
  };

  const handleAddToCart = () => {
    setCart([...cart, { name: 'Mega Planeta Burger', price: 32.90, modifiers: [] }]);
  };

  const total = cart.reduce((acc, item) => acc + item.price, 0);

  return (
    <div className="flex h-screen w-full bg-dark-900 text-white font-sans overflow-hidden">
      <main className="flex-1 flex flex-col p-6 overflow-y-auto">
        <header className="flex justify-between items-center mb-8">
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-3xl font-bold tracking-tight text-white">Planeta Lanches</h1>
              {!isOnline && (
                <span className="bg-red-500 text-white text-xs font-bold px-2 py-1 rounded animate-pulse tracking-widest">
                  OFFLINE
                </span>
              )}
            </div>
            <p className="text-gray-400 text-sm mt-1 uppercase tracking-widest">Caixa & Atendimento</p>
          </div>
          <div className="flex gap-4">
            {['DOGÕES', 'HAMBÚRGUERES', 'BEBIDAS'].map(cat => (
              <button 
                key={cat} 
                className="px-6 py-2 rounded-md bg-dark-800 border border-dark-700 hover:border-brasa-500 hover:text-brasa-500 transition-all font-semibold uppercase tracking-wider"
              >
                {cat}
              </button>
            ))}
          </div>
        </header>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
          <div 
            onClick={handleAddToCart}
            className="group relative bg-dark-800 rounded-xl p-5 border border-dark-700 hover:border-brasa-500 transition-all cursor-pointer shadow-glass hover:shadow-brasa-glow"
          >
            <div className="flex justify-between items-start mb-4">
              <h3 className="text-lg font-bold text-gray-100 group-hover:text-brasa-500 transition-colors">Mega Planeta Burger</h3>
              <span className="bg-dark-900 text-brasa-500 px-3 py-1 rounded-full text-sm font-bold border border-brasa-500/30">
                R$ 32,90
              </span>
            </div>
            <p className="text-gray-400 text-sm line-clamp-2">2x Blend 160g, Cheddar, Bacon crocante, Molho da casa.</p>
            <button className="mt-4 w-full bg-dark-700 group-hover:bg-brasa-500 text-white font-bold py-2 rounded-lg transition-colors">
              Adicionar
            </button>
          </div>
        </div>
      </main>

      <aside className="w-96 bg-dark-800 border-l border-dark-700 flex flex-col shadow-2xl z-10">
        <div className="p-6 border-b border-dark-700 flex justify-between items-center">
          <h2 className="text-xl font-bold text-white">Comanda Atual</h2>
          <span className="bg-brasa-500 text-white text-xs font-bold px-2 py-1 rounded-md">MESA 04</span>
        </div>
        
        <div className="p-6 border-b border-dark-700 bg-dark-900">
          <label className="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
            Cliente / Fidelidade (Telemóvel)
          </label>
          <div className="flex gap-2">
            <input 
              type="tel" 
              placeholder="(81) 99999-9999" 
              value={customerPhone}
              onChange={(e) => setCustomerPhone(e.target.value)}
              className="w-full bg-dark-800 border border-dark-700 rounded-lg p-3 text-white focus:border-brasa-500 outline-none transition-colors"
            />
          </div>
          {customerPhone.length > 8 && (
            <p className="text-brasa-500 text-xs font-bold mt-2 animate-pulse">
              Associando 5% de Cashback a esta compra...
            </p>
          )}
        </div>

        <div className="flex-1 overflow-y-auto p-6 space-y-4">
          {cart.length === 0 ? (
            <div className="text-center text-gray-500 mt-10 font-bold">Comanda Vazia</div>
          ) : (
            cart.map((item, index) => (
              <div key={index} className="bg-dark-900 p-4 rounded-lg border border-dark-700">
                <div className="flex justify-between font-bold">
                  <span>1x {item.name}</span>
                  <span>R$ {item.price.toFixed(2)}</span>
                </div>
              </div>
            ))
          )}
        </div>

        <div className="p-6 bg-dark-900 border-t border-dark-700">
          <div className="flex justify-between text-gray-400 mb-2">
            <span>Subtotal</span>
            <span>R$ {total.toFixed(2)}</span>
          </div>
          <div className="flex justify-between text-2xl font-bold text-white mb-6">
            <span>Total</span>
            <span>R$ {total.toFixed(2)}</span>
          </div>
          
          <button 
            onClick={handleCheckout}
            disabled={cart.length === 0}
            className={`w-full font-bold py-4 rounded-xl transition-all uppercase tracking-widest disabled:opacity-50 disabled:active:scale-100 active:scale-95 ${
              isOnline
                ? 'bg-brasa-500 hover:bg-brasa-600 text-white shadow-brasa-glow'
                : 'bg-yellow-600 hover:bg-yellow-700 text-white shadow-glass'
            }`}
          >
            {isOnline ? 'Finalizar Pedido' : 'Guardar na Fila Local'}
          </button>
        </div>
      </aside>
    </div>
  );
}