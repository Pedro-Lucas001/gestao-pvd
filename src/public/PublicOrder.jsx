import { useState, useEffect, useCallback } from 'react';
import { supabase } from '../lib/supabase';

export default function PublicOrder() {
  const [cart, setCart] = useState([]);
  const [step, setStep] = useState('MENU'); // MENU, CHECKOUT, PAYMENT, SUCCESS
  
  // Estados para o PIX Dinâmico
  const [qrCodeData, setQrCodeData] = useState(null);
  const [currentOrderId, setCurrentOrderId] = useState(null);

  // Envolvemos em useCallback para estabilizar a referência da função
  const resetTotem = useCallback(() => {
    setCart([]);
    setStep('MENU');
    setQrCodeData(null);
    setCurrentOrderId(null);
  }, []);

  // Temporizador de inatividade limpo usando setTimeout em vez de setState síncrono no effect
  useEffect(() => {
    let timeout;
    if (cart.length > 0 && step !== 'PAYMENT' && step !== 'SUCCESS') {
      // Se passar 120 segundos (2 minutos) sem interação, reseta o totem
      timeout = setTimeout(() => {
        resetTotem();
      }, 120000);
    }

    const resetIdleTimer = () => {
      if (timeout) clearTimeout(timeout);
      if (cart.length > 0 && step !== 'PAYMENT' && step !== 'SUCCESS') {
        timeout = setTimeout(() => {
          resetTotem();
        }, 120000);
      }
    };

    window.addEventListener('click', resetIdleTimer);
    window.addEventListener('touchstart', resetIdleTimer);

    return () => {
      if (timeout) clearTimeout(timeout);
      window.removeEventListener('click', resetIdleTimer);
      window.removeEventListener('touchstart', resetIdleTimer);
    };
  }, [cart.length, step, resetTotem]);

  const addToCart = (product) => {
    setCart([...cart, product]);
  };

  const total = cart.reduce((acc, item) => acc + item.price, 0);

  // Integração PIX e Supabase Edge Functions
  const handlePayment = async () => {
    setStep('PAYMENT');
    setQrCodeData(null);
    
    try {
      const { data, error } = await supabase.functions.invoke('checkout-payment', {
        body: { total_amount: total, items: cart, source: 'totem' }
      });

      if (error) throw error;
      
      setQrCodeData(data.qr_code_payload); 
      setCurrentOrderId(data.order_id);

      const channel = supabase
        .channel(`order-${data.order_id}`)
        .on('postgres_changes', { 
          event: 'UPDATE', 
          schema: 'public', 
          table: 'orders',
          filter: `id=eq.${data.order_id}` 
        }, (payload) => {
          if (payload.new.status === 'preparing' || payload.new.status === 'paid') {
            setStep('SUCCESS');
            setTimeout(resetTotem, 5000);
            supabase.removeChannel(channel);
          }
        })
        .subscribe();

    } catch (err) {
      console.error('Erro ao gerar PIX:', err);
      alert('Ocorreu um erro ao gerar o pagamento. Por favor, tente novamente.');
      setStep('CHECKOUT');
    }
  };

  return (
    <div className="h-screen w-full bg-dark-900 text-white font-sans flex flex-col select-none">
      
      {/* HEADER DO TOTEM */}
      <header className="bg-dark-800 p-6 flex justify-between items-center shadow-glass border-b border-dark-700">
        <h1 className="text-4xl font-bold tracking-tighter">
          Planeta<span className="text-brasa-500">Lanches</span>
        </h1>
        {step !== 'SUCCESS' && (
          <button 
            onClick={resetTotem}
            className="bg-dark-700 text-gray-400 px-6 py-3 rounded-xl font-bold text-lg hover:text-white border border-dark-700 transition-colors"
          >
            Cancelar Pedido
          </button>
        )}
      </header>

      {/* TELA DE MENU */}
      {step === 'MENU' && (
        <main className="flex-1 flex overflow-hidden">
          <aside className="w-48 bg-dark-800 border-r border-dark-700 flex flex-col gap-2 p-4">
            {['Destaques', 'Hambúrgueres', 'Bebidas'].map(cat => (
              <button key={cat} className="h-20 bg-dark-900 rounded-xl font-bold text-lg border border-dark-700 text-gray-300 active:bg-brasa-500 active:text-white transition-colors">
                {cat}
              </button>
            ))}
          </aside>

          <section className="flex-1 p-8 grid grid-cols-3 gap-6 overflow-y-auto pb-32">
            <div 
              onClick={() => addToCart({ name: 'Mega Planeta Burger', price: 32.90 })}
              className="bg-dark-800 rounded-3xl p-6 border-2 border-dark-700 active:border-brasa-500 flex flex-col items-center text-center gap-4 cursor-pointer shadow-glass transition-all"
            >
              <div className="w-32 h-32 bg-dark-900 rounded-full border border-dark-700 mb-2"></div>
              <h3 className="text-2xl font-bold text-white">Mega Planeta Burger</h3>
              <span className="text-brasa-500 font-bold text-xl">R$ 32,90</span>
            </div>
          </section>

          {cart.length > 0 && (
            <div className="absolute bottom-0 left-48 right-0 p-6 bg-dark-800 border-t border-dark-700 shadow-2xl flex justify-between items-center z-10">
              <div className="text-2xl font-bold">
                <span className="text-gray-400 mr-2">{cart.length} itens</span>
                <span className="text-white">R$ {total.toFixed(2)}</span>
              </div>
              <button 
                onClick={() => setStep('CHECKOUT')}
                className="bg-brasa-500 hover:bg-brasa-600 text-white text-2xl font-bold px-12 py-6 rounded-2xl shadow-brasa-glow active:scale-95 transition-all uppercase tracking-widest"
              >
                Revisar e Pagar
              </button>
            </div>
          )}
        </main>
      )}

      {/* TELA DE CHECKOUT */}
      {step === 'CHECKOUT' && (
        <div className="flex-1 flex flex-col items-center justify-center p-8 bg-dark-900">
          <div className="w-full max-w-2xl bg-dark-800 p-8 rounded-3xl border border-dark-700 shadow-glass">
            <h2 className="text-3xl font-bold mb-8 text-center text-white">Confira o seu Pedido</h2>
            <div className="space-y-4 mb-8 max-h-96 overflow-y-auto">
              {cart.map((item, i) => (
                <div key={i} className="flex justify-between text-xl bg-dark-900 p-4 rounded-xl border border-dark-700 text-gray-200">
                  <span className="font-bold">{item.name}</span>
                  <span className="text-brasa-500 font-bold">R$ {item.price.toFixed(2)}</span>
                </div>
              ))}
            </div>
            
            <div className="flex justify-between items-center mb-8 border-t border-dark-700 pt-6">
              <span className="text-2xl text-gray-400 font-bold">Total:</span>
              <span className="text-4xl text-white font-bold">R$ {total.toFixed(2)}</span>
            </div>

            <button 
              onClick={handlePayment}
              className="w-full bg-green-500 hover:bg-green-600 text-white text-3xl font-bold py-6 rounded-2xl shadow-[0_4px_20px_-2px_rgba(34,197,94,0.4)] active:scale-95 transition-all uppercase tracking-widest"
            >
              Pagar com PIX
            </button>
          </div>
        </div>
      )}

      {/* TELA DE PAGAMENTO (CDS - QR CODE) */}
      {step === 'PAYMENT' && (
        <div className="flex-1 flex flex-col items-center justify-center p-8 bg-dark-900">
          <div className="bg-dark-800 p-12 rounded-3xl border border-dark-700 shadow-brasa-glow flex flex-col items-center text-center w-full max-w-xl">
            <h2 className="text-4xl font-bold mb-4 text-white">Escaneie para Pagar</h2>
            <p className="text-gray-400 text-xl mb-8">Abra o app do seu banco e aponte a câmara</p>
            
            <div className="w-64 h-64 bg-white rounded-xl mb-8 flex items-center justify-center p-4">
              {qrCodeData ? (
                <img 
                  src={`https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${encodeURIComponent(qrCodeData)}`} 
                  alt="QR Code PIX" 
                  className="w-full h-full object-contain"
                />
              ) : (
                <div className="flex flex-col items-center justify-center">
                  <div className="w-10 h-10 border-4 border-gray-200 border-t-brasa-500 rounded-full animate-spin mb-4"></div>
                  <span className="text-gray-500 font-bold">A gerar código PIX...</span>
                </div>
              )}
            </div>

            <p className="text-brasa-500 text-4xl font-bold mb-2">R$ {total.toFixed(2)}</p>
            <p className="text-gray-500 text-sm animate-pulse">A aguardar confirmação do pagamento...</p>
          </div>
        </div>
      )}

      {/* TELA DE SUCESSO */}
      {step === 'SUCCESS' && (
        <div className="flex-1 flex flex-col items-center justify-center p-8 bg-dark-900">
          <div className="bg-dark-800 p-12 rounded-3xl border border-green-500/50 shadow-[0_4px_20px_-2px_rgba(34,197,94,0.4)] flex flex-col items-center text-center w-full max-w-xl">
            <div className="w-24 h-24 bg-green-500 rounded-full flex items-center justify-center mb-6">
              <svg className="w-12 h-12 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="3" d="M5 13l4 4L19 7"></path>
              </svg>
            </div>
            <h2 className="text-4xl font-bold mb-4 text-white">Pagamento Confirmado!</h2>
            <p className="text-gray-300 text-xl mb-2">O seu pedido já está a ser preparado na cozinha.</p>
            <p className="text-brasa-500 text-2xl font-bold mt-4">
              Senha: #{currentOrderId ? currentOrderId.slice(0,4).toUpperCase() : '0000'}
            </p>
          </div>
        </div>
      )}
    </div>
  );
}