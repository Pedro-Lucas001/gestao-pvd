import React, { useState, useEffect } from 'react';
// import { supabase } from '../lib/supabase'; // Para a validação real no banco

export default function PinPad({ onUnlock }) {
  const [pin, setPin] = useState('');
  const [error, setError] = useState(false);
  const [attempts, setAttempts] = useState(0);
  const [lockoutTime, setLockoutTime] = useState(0);

  const MAX_ATTEMPTS = 5;
  const LOCKOUT_SECONDS = 60; // Bloqueio de 1 minuto

  // Temporizador de bloqueio
  useEffect(() => {
    let timer;
    if (lockoutTime > 0) {
      timer = setInterval(() => {
        setLockoutTime((prev) => prev - 1);
      }, 1000);
    } else if (lockoutTime === 0 && attempts >= MAX_ATTEMPTS) {
      setAttempts(0); // Reseta as tentativas após o castigo
      setError(false);
    }
    return () => clearInterval(timer);
  }, [lockoutTime, attempts]);

  // Auto-submit quando atinge 4 dígitos
  useEffect(() => {
    if (pin.length === 4) {
      validatePin();
    }
  }, [pin]);

  const validatePin = async () => {
    if (lockoutTime > 0) return;

    // TODO: Substituir pela chamada real ao Supabase
    // const { data } = await supabase.from('profiles').select('*').eq('pin_code', pin).single();
    const isValid = pin === '1234'; // Simulação de PIN correto

    if (isValid) {
      setAttempts(0);
      setPin('');
      onUnlock(); // Libera o acesso ao PDV
    } else {
      const newAttempts = attempts + 1;
      setAttempts(newAttempts);
      setPin('');
      setError(true);

      if (newAttempts >= MAX_ATTEMPTS) {
        setLockoutTime(LOCKOUT_SECONDS);
      }
    }
  };

  const handlePress = (num) => {
    if (lockoutTime > 0) return;
    if (pin.length < 4) {
      setPin((prev) => prev + num);
      setError(false);
    }
  };

  const handleDelete = () => {
    if (lockoutTime > 0) return;
    setPin((prev) => prev.slice(0, -1));
    setError(false);
  };

  return (
    <div className="flex flex-col items-center justify-center min-h-screen bg-dark-900 font-sans absolute inset-0 z-50">
      <div className="bg-dark-800 p-8 rounded-2xl shadow-glass border border-dark-700 w-80 flex flex-col items-center">
        
        {/* Cabeçalho */}
        <h2 className="text-2xl font-bold text-white mb-2">Acesso Restrito</h2>
        {lockoutTime > 0 ? (
          <p className="text-red-500 font-bold text-sm animate-pulse mb-6">
            Bloqueado. Tente em {lockoutTime}s
          </p>
        ) : (
          <p className="text-gray-400 text-sm mb-6 uppercase tracking-widest">
            {error ? (
              <span className="text-brasa-500 font-bold">PIN Incorreto ({attempts}/{MAX_ATTEMPTS})</span>
            ) : (
              'Insira o seu PIN'
            )}
          </p>
        )}

        {/* Display do PIN (Bolinhas) */}
        <div className={`flex gap-4 mb-8 ${error ? 'animate-bounce' : ''}`}>
          {[...Array(4)].map((_, i) => (
            <div 
              key={i} 
              className={`w-4 h-4 rounded-full transition-all duration-300 ${
                i < pin.length 
                  ? 'bg-brasa-500 shadow-brasa-glow' 
                  : 'bg-dark-700 border border-dark-700'
              }`}
            />
          ))}
        </div>

        {/* Teclado Numérico */}
        <div className="grid grid-cols-3 gap-4 w-full">
          {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((num) => (
            <button
              key={num}
              onClick={() => handlePress(num.toString())}
              disabled={lockoutTime > 0}
              className="h-16 rounded-xl bg-dark-700 text-white text-2xl font-bold border border-dark-700 hover:border-brasa-500 hover:bg-dark-800 active:scale-95 transition-all disabled:opacity-50 disabled:active:scale-100"
            >
              {num}
            </button>
          ))}
          
          {/* Botões da Linha Inferior */}
          <div className="h-16"></div> {/* Espaço Vazio */}
          <button
            onClick={() => handlePress('0')}
            disabled={lockoutTime > 0}
            className="h-16 rounded-xl bg-dark-700 text-white text-2xl font-bold border border-dark-700 hover:border-brasa-500 hover:bg-dark-800 active:scale-95 transition-all disabled:opacity-50 disabled:active:scale-100"
          >
            0
          </button>
          <button
            onClick={handleDelete}
            disabled={lockoutTime > 0 || pin.length === 0}
            className="h-16 rounded-xl bg-dark-800 text-gray-400 text-xl font-bold hover:text-brasa-500 active:scale-95 transition-all flex items-center justify-center disabled:opacity-50 disabled:active:scale-100"
          >
            {/* Ícone de Backspace (Apagar) */}
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2M3 12l6.414 6.414a2 2 0 001.414.586H19a2 2 0 002-2V7a2 2 0 00-2-2h-8.172a2 2 0 00-1.414.586L3 12z"></path>
            </svg>
          </button>
        </div>

      </div>
    </div>
  );
}