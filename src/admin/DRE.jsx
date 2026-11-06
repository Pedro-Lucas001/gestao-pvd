import React, { useState, useEffect } from 'react';
// import { supabase } from '../lib/supabase';

export default function DRE() {
  // Simulação de agregação de dados do Supabase
  const [metrics, setMetrics] = useState({
    faturacaoBruta: 12450.00,
    cmv: 3850.00, // Custo total de ingredientes deduzidos
    despesasFixas: 2100.00,
    pedidosTotal: 342
  });

  const lucroLiquido = metrics.faturacaoBruta - metrics.cmv - metrics.despesasFixas;
  const margemLucro = ((lucroLiquido / metrics.faturacaoBruta) * 100).toFixed(1);

  return (
    <div className="min-h-screen bg-dark-900 text-white font-sans p-8 overflow-y-auto">
      <header className="mb-10">
        <h1 className="text-4xl font-bold tracking-tight">Dashboard <span className="text-brasa-500">Executivo</span></h1>
        <p className="text-gray-400 mt-2">Demonstração de Resultados (Mês Atual)</p>
      </header>

      {/* Cartões de KPI Principais */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-10">
        {/* Faturação Bruta */}
        <div className="bg-dark-800 p-6 rounded-2xl border border-dark-700 shadow-glass">
          <h3 className="text-gray-400 font-bold mb-2 uppercase tracking-wider text-sm">Faturação Bruta</h3>
          <p className="text-3xl font-bold text-white">R$ {metrics.faturacaoBruta.toFixed(2)}</p>
          <span className="text-green-500 text-sm font-bold flex items-center gap-1 mt-2">
            +14% vs mês anterior
          </span>
        </div>

        {/* CMV (Custos de Produção) */}
        <div className="bg-dark-800 p-6 rounded-2xl border border-dark-700 shadow-glass">
          <h3 className="text-gray-400 font-bold mb-2 uppercase tracking-wider text-sm">Custo (CMV)</h3>
          <p className="text-3xl font-bold text-red-400">R$ {metrics.cmv.toFixed(2)}</p>
          <span className="text-gray-500 text-sm font-bold mt-2 block">
            {((metrics.cmv / metrics.faturacaoBruta) * 100).toFixed(1)}% da faturação
          </span>
        </div>

        {/* Lucro Líquido (Glow Laranja) */}
        <div className="bg-dark-800 p-6 rounded-2xl border border-brasa-500/50 shadow-brasa-glow relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-brasa-500/10 rounded-full blur-3xl"></div>
          <h3 className="text-gray-400 font-bold mb-2 uppercase tracking-wider text-sm">Lucro Líquido</h3>
          <p className="text-4xl font-bold text-brasa-500">R$ {lucroLiquido.toFixed(2)}</p>
          <span className="text-white text-sm font-bold mt-2 block">
            Margem: {margemLucro}%
          </span>
        </div>

        {/* Volume de Pedidos */}
        <div className="bg-dark-800 p-6 rounded-2xl border border-dark-700 shadow-glass">
          <h3 className="text-gray-400 font-bold mb-2 uppercase tracking-wider text-sm">Total Pedidos</h3>
          <p className="text-3xl font-bold text-white">{metrics.pedidosTotal}</p>
          <span className="text-gray-500 text-sm font-bold mt-2 block">Ticket Médio: R$ {(metrics.faturacaoBruta / metrics.pedidosTotal).toFixed(2)}</span>
        </div>
      </div>

      {/* Secção de Gráficos e Tabelas Analíticas */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        
        {/* Produtos Mais Vendidos */}
        <div className="lg:col-span-2 bg-dark-800 p-6 rounded-2xl border border-dark-700 shadow-glass">
          <h3 className="text-xl font-bold text-white mb-6">Top Produtos Vendidos</h3>
          <div className="space-y-4">
            {[
              { nome: 'Mega Planeta Burger', qtd: 145, valor: 4770.50, barWidth: '85%' },
              { nome: 'Combo Casal', qtd: 98, valor: 3910.20, barWidth: '60%' },
              { nome: 'Batata Rústica com Cheddar', qtd: 112, valor: 1680.00, barWidth: '45%' },
            ].map((prod, i) => (
              <div key={i} className="flex flex-col gap-2">
                <div className="flex justify-between text-sm font-bold">
                  <span className="text-gray-300">{prod.nome} <span className="text-gray-500">({prod.qtd}x)</span></span>
                  <span className="text-brasa-500">R$ {prod.valor.toFixed(2)}</span>
                </div>
                <div className="w-full bg-dark-900 rounded-full h-2">
                  <div className="bg-brasa-500 h-2 rounded-full" style={{ width: prod.barWidth }}></div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Alertas de Estoque Cruzado (Inteligência) */}
        <div className="bg-dark-800 p-6 rounded-2xl border border-dark-700 shadow-glass">
          <h3 className="text-xl font-bold text-white mb-6 flex items-center gap-2">
            <svg className="w-5 h-5 text-yellow-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z"></path></svg>
            Alertas de Insumos
          </h3>
          <ul className="space-y-4">
            <li className="bg-dark-900 p-4 rounded-xl border border-red-500/30">
              <p className="text-red-400 font-bold text-sm">Cebola Caramelizada</p>
              <p className="text-gray-400 text-xs mt-1">Stock crítico: Restam 1.2kg (Suficiente para ~20 burgers).</p>
            </li>
            <li className="bg-dark-900 p-4 rounded-xl border border-yellow-500/30">
              <p className="text-yellow-400 font-bold text-sm">Bacon em Tiras</p>
              <p className="text-gray-400 text-xs mt-1">Abaixo da margem de segurança (4.5kg).</p>
            </li>
          </ul>
        </div>

      </div>
    </div>
  );
}