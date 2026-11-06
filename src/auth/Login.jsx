import React, { useState, useEffect } from 'react';
// import { useNavigate } from 'react-router-dom';
// import { supabase } from '../lib/supabase';

export default function Login() {
  const [pin, setPin] = useState('');
  const [error, setError] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  // const navigate = useNavigate();

  // Auto-submit quando o PIN atinge 4 dígitos
  useEffect(() => {
    if (pin.length === 4) {
      handleLogin();
    }
  }, [pin]);

  const handleLogin = async () => {
    setIsLoading(true);
    setError(false);

    try {
      // SIMULAÇÃO: Aqui faria a consulta real ao Supabase
      // const { data, error } = await supabase.from('profiles').select('role, department').eq('pin_code', pin).single();
      
      // Lógica simulada de separação:
      // Se PIN for 1111 -> Caixa (PDV)
      // Se PIN for 2222 -> Cozinha (KDS)
      // Se PIN for 3333 -> Admin (Back-office)
      
      setTimeout(() => {
        if (pin === '1111') {
          alert('Redirecionando para o CAIXA (PDV)...');
          // navigate('/pdv');
        } else if (pin === '2222') {
          alert('Redirecionando para a COZINHA (KDS)...');
          // navigate('/kds');
        } else if (pin === '3333') {
          alert('Redirecionando para o BACK-OFFICE...');
          // navigate('/admin');
        } else {
          setError(true);
          setPin('');
        }
        setIsLoading(false);
      }, 800);

    } catch (err) {
      setError(true);
      setPin('');
      setIsLoading(false);
    }
  };

  const handlePress = (num) => {
    if (pin.length < 4 && !isLoading) {
      setPin(prev => prev + num);
      setError(false);
    }
  };

  const handleDelete = () => {
    if (!isLoading) {
      setPin(prev => prev.slice(0, -1));
      setError(false);
    }
  };

  return (
    <div className="min-h-screen bg-dark-900 flex items-center justify-center font-sans p-4">
      {/* Container Principal */}
      <div className="bg-dark-800 p-10 rounded-3xl shadow-glass border border-dark-700 w-full max-w-md flex flex-col items-center">
        
        {/* Logo e Branding */}
        <div className="mb-8 text-center">
          <h1 className="text-4xl font-bold text-white tracking-tighter mb-1">
            Planeta<span className="text-brasa-500">Lanches</span>
          </h1>
          <p className="text-gray-400 uppercase tracking-widest text-sm font-bold">
            Portal de Acesso
          </p>
        </div>

        {/* Feedback Visual do PIN */}
        <div className="mb-8 flex flex-col items-center h-16 justify-center">
          {isLoading ? (
            <div className="flex items-center gap-3 text-brasa-500 font-bold">
              <div className="w-5 h-5 border-4 border-brasa-500 border-t-transparent rounded-full animate-spin"></div>
              Autenticando...
            </div>
          ) : (
            <>
              <div className={`flex gap-4 ${error ? 'animate-bounce' : ''}`}>
                {[...Array(4)].map((_, i) => (
                  <div 
                    key={i} 
                    className={`w-5 h-5 rounded-full transition-all duration-300 ${
                      i < pin.length 
                        ? (error ? 'bg-red-500 shadow-[0_0_15px_rgba(239,68,68,0.5)]' : 'bg-brasa-500 shadow-brasa-glow')
                        : 'bg-dark-900 border border-dark-700'
                    }`}
                  />
                ))}
              </div>
              {error && <p className="text-red-500 text-xs font-bold mt-4 uppercase">PIN Inválido</p>}
            </>
          )}
        </div>

        {/* Teclado Numérico Gigante para Ecrãs Touch */}
        <div className="grid grid-cols-3 gap-4 w-full">
          {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((num) => (
            <button
              key={num}
              onClick={() => handlePress(num.toString())}
              disabled={isLoading}
              className="h-20 rounded-2xl bg-dark-700 text-white text-3xl font-bold border border-dark-700 hover:border-brasa-500 hover:bg-dark-800 active:scale-95 transition-all shadow-sm"
            >
              {num}
            </button>
          ))}
          
          <div className="h-20"></div> {/* Espaço vazio inferior esquerdo */}
          
          <button
            onClick={() => handlePress('0')}
            disabled={isLoading}
            className="h-20 rounded-2xl bg-dark-700 text-white text-3xl font-bold border border-dark-700 hover:border-brasa-500 hover:bg-dark-800 active:scale-95 transition-all shadow-sm"
          >
            0
          </button>
          
          <button
            onClick={handleDelete}
            disabled={isLoading || pin.length === 0}
            className="h-20 rounded-2xl bg-dark-900 text-gray-400 text-xl font-bold hover:text-red-500 active:scale-95 transition-all flex items-center justify-center border border-dark-700"
          >
            {/* Ícone Backspace */}
            <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2M3 12l6.414 6.414a2 2 0 001.414.586H19a2 2 0 002-2V7a2 2 0 00-2-2h-8.172a2 2 0 00-1.414.586L3 12z"></path>
            </svg>
          </button>
        </div>

      </div>
    </div>
  );
}