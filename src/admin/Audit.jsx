import React, { useState } from 'react';
import { supabase } from '../lib/supabase';

export default function Audit() {
  const [phoneToErase, setPhoneToErase] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState(null);

  const handleLgpdDeletion = async (e) => {
    e.preventDefault();
    if (!phoneToErase) return;
    
    // Confirmação dupla, exigida em operações destrutivas
    const confirm = window.confirm(`ATENÇÃO: Deseja anonimizar irreversivelmente os dados do número ${phoneToErase}? O histórico de vendas será mantido, mas a identidade será apagada.`);
    
    if (!confirm) return;
    setIsLoading(true);
    setMessage(null);

    try {
      // Comunica com a Edge Function
      const { data, error } = await supabase.functions.invoke('eco-lgpd', {
        body: { phone: phoneToErase, action: 'delete' }
      });

      if (error) throw error;
      
      setMessage({ type: 'success', text: data.message });
      setPhoneToErase('');
    } catch (err) {
      setMessage({ type: 'error', text: 'Erro ao anonimizar cliente. Verifique se o número existe.' });
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-dark-900 text-white font-sans p-8">
      <header className="mb-10 border-b border-dark-700 pb-6">
        <h1 className="text-4xl font-bold tracking-tight">Segurança & <span className="text-brasa-500">Auditoria</span></h1>
        <p className="text-gray-400 mt-2">Trilhas de sistema e conformidade legal</p>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        
        {/* Painel LGPD */}
        <div className="bg-dark-800 p-8 rounded-2xl border border-red-500/30 shadow-glass">
          <div className="flex items-center gap-3 mb-6">
            <svg className="w-8 h-8 text-red-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 15v2m-6 4h12a2 2 0 002-2v-6a2 2 0 00-2-2H6a2 2 0 00-2 2v6a2 2 0 002 2zm10-10V7a4 4 0 00-8 0v4h8z"></path></svg>
            <h2 className="text-2xl font-bold text-white">Conformidade LGPD</h2>
          </div>
          <p className="text-gray-400 text-sm mb-6">
            O "Direito ao Esquecimento" permite que os clientes solicitem a exclusão dos seus dados pessoais. Esta ferramenta anonimiza o nome, telemóvel e zera os saldos de cashback, mantendo a integridade matemática da faturação.
          </p>

          <form onSubmit={handleLgpdDeletion} className="space-y-4">
            <div>
              <label className="block text-xs font-bold text-gray-400 uppercase tracking-wider mb-2">
                Telemóvel do Cliente
              </label>
              <input 
                type="tel" 
                value={phoneToErase}
                onChange={(e) => setPhoneToErase(e.target.value)}
                placeholder="Ex: (81) 99999-9999"
                className="w-full bg-dark-900 border border-dark-700 rounded-xl p-4 text-white focus:border-red-500 outline-none transition-colors"
              />
            </div>
            <button 
              type="submit"
              disabled={isLoading || !phoneToErase}
              className="w-full bg-red-600 hover:bg-red-700 disabled:bg-dark-700 disabled:text-gray-500 text-white font-bold py-4 rounded-xl transition-all uppercase tracking-widest flex items-center justify-center gap-2"
            >
              {isLoading ? 'A Processar...' : 'Anonimizar Dados (Irreversível)'}
            </button>
          </form>

          {message && (
            <div className={`mt-6 p-4 rounded-xl font-bold ${message.type === 'success' ? 'bg-green-500/20 text-green-400 border border-green-500/30' : 'bg-red-500/20 text-red-400 border border-red-500/30'}`}>
              {message.text}
            </div>
          )}
        </div>

        {/* Placeholder para a Tabela de Logs de Auditoria */}
        <div className="bg-dark-800 p-8 rounded-2xl border border-dark-700 shadow-glass">
          <h2 className="text-2xl font-bold text-white mb-6">Logs Recentes</h2>
          <div className="space-y-3">
            <div className="bg-dark-900 p-4 rounded-xl border border-dark-700">
              <span className="text-xs font-bold text-gray-500 uppercase">Há 5 min</span>
              <p className="text-gray-300 font-bold mt-1">Anonimização LGPD executada</p>
              <p className="text-brasa-500 text-sm">Operador: Admin Principal</p>
            </div>
          </div>
        </div>

      </div>
    </div>
  );
}