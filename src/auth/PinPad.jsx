import { useState, useEffect, useCallback } from 'react';

export default function PinPad({ onSuccess }) {
  const [pin, setPin] = useState('');
  const [error, setError] = useState(false);
  const [attempts, setAttempts] = useState(0);
  const [lockoutTime, setLockoutTime] = useState(0);

  const MAX_ATTEMPTS = 3;

  const validatePin = useCallback(async (currentPin) => {
    if (lockoutTime > 0) return;

    try {
      if (currentPin === '1234') {
        setAttempts(0);
        setError(false);
        if (onSuccess) onSuccess();
      } else {
        throw new Error('PIN incorreto');
      }
    } catch {
      const newAttempts = attempts + 1;
      setAttempts(newAttempts);
      setError(true);
      setPin('');

      if (newAttempts >= MAX_ATTEMPTS) {
        setLockoutTime(30);
      }
    }
  }, [attempts, lockoutTime, onSuccess]);

  // Controlo do temporizador (este useEffect é permitido pois sincroniza com o relógio do sistema externo)
  useEffect(() => {
    let timer;
    if (lockoutTime > 0) {
      timer = setInterval(() => {
        setLockoutTime(prev => prev - 1);
      }, 1000);
    }
    return () => clearInterval(timer);
  }, [lockoutTime]);

  const handlePress = (num) => {
    if (lockoutTime > 0 || pin.length >= 4) return;
    const newPin = pin + num;
    setPin(newPin);
    setError(false);

    if (newPin.length === 4) {
      validatePin(newPin);
    }
  };

  const handleDelete = () => {
    if (lockoutTime > 0) return;
    setPin(prev => prev.slice(0, -1));
    setError(false);
  };

  return (
    <div className="flex flex-col items-center justify-center p-6 bg-dark-800 rounded-2xl border border-dark-700 shadow-glass max-w-xs mx-auto">
      <div className="mb-6 text-center">
        <h3 className="text-xl font-bold text-white mb-1">Insira o PIN</h3>
        {lockoutTime > 0 ? (
          <p className="text-red-500 font-bold text-sm">Bloqueado. Aguarde {lockoutTime}s</p>
        ) : (
          <p className="text-gray-400 text-xs">Tentativas restantes: {MAX_ATTEMPTS - attempts}</p>
        )}
      </div>

      <div className="flex gap-3 mb-6">
        {[...Array(4)].map((_, i) => (
          <div 
            key={i} 
            className={`w-4 h-4 rounded-full transition-all ${
              i < pin.length 
                ? (error ? 'bg-red-500' : 'bg-brasa-500 shadow-brasa-glow') 
                : 'bg-dark-900 border border-dark-700'
            }`}
          />
        ))}
      </div>

      <div className="grid grid-cols-3 gap-3 w-full">
        {[1, 2, 3, 4, 5, 6, 7, 8, 9].map(num => (
          <button
            key={num}
            onClick={() => handlePress(num.toString())}
            disabled={lockoutTime > 0}
            className="h-14 rounded-xl bg-dark-700 text-white text-xl font-bold hover:border-brasa-500 border border-dark-700 active:scale-95 disabled:opacity-40 transition-all"
          >
            {num}
          </button>
        ))}
        <div className="h-14"></div>
        <button
          onClick={() => handlePress('0')}
          disabled={lockoutTime > 0}
          className="h-14 rounded-xl bg-dark-700 text-white text-xl font-bold hover:border-brasa-500 border border-dark-700 active:scale-95 disabled:opacity-40 transition-all"
        >
          0
        </button>
        <button
          onClick={handleDelete}
          disabled={lockoutTime > 0 || pin.length === 0}
          className="h-14 rounded-xl bg-dark-900 text-gray-400 font-bold hover:text-red-500 border border-dark-700 active:scale-95 flex items-center justify-center disabled:opacity-40 transition-all"
        >
          ⌫
        </button>
      </div>
    </div>
  );
}