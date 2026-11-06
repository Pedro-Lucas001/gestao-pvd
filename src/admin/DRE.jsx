import { useState } from 'react';

export default function DRE() {
  const [metrics] = useState({
    faturacaoBruta: 12450.00,
    cmv: 3850.00,
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

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-6 mb-10">
        <div className="bg-dark-800 p-6 rounded-2xl border border-dark-700 shadow-glass">
          <h3 className="text-gray-400 font-bold mb-2 uppercase tracking-wider text-sm">Faturação Bruta</h3>
          <p className="text-3xl font-bold text-white">R$ {metrics.faturacaoBruta.toFixed(2)}</p>
          <span className="text-green-500 text-sm font-bold flex items-center gap-1 mt-2">
            +14% vs mês anterior
          </span>
        </div>

        <div className="bg-dark-800 p-6 rounded-2xl border border-dark-700 shadow-glass">
          <h3 className="text-gray-400 font-bold mb-2 uppercase tracking-wider text-sm">Custo (CMV)</h3>
          <p className="text-3xl font-bold text-red-400">R$ {metrics.cmv.toFixed(2)}</p>
          <span className="text-gray-500 text-sm font-bold mt-2 block">
            {((metrics.cmv / metrics.faturacaoBruta) * 100).toFixed(1)}% da faturação
          </span>
        </div>

        <div className="bg-dark-800 p-6 rounded-2xl border border-brasa-500/50 shadow-brasa-glow relative overflow-hidden">
          <div className="absolute top-0 right-0 w-32 h-32 bg-brasa-500/10 rounded-full blur-3xl"></div>
          <h3 className="text-gray-400 font-bold mb-2 uppercase tracking-wider text-sm">Lucro Líquido</h3>
          <p className="text-4xl font-bold text-brasa-500">R$ {lucroLiquido.toFixed(2)}</p>
          <span className="text-white text-sm font-bold mt-2 block">
            Margem: {margemLucro}%
          </span>
        </div>

        <div className="bg-dark-800 p-6 rounded-2xl border border-dark-700 shadow-glass">
          <h3 className="text-gray-400 font-bold mb-2 uppercase tracking-wider text-sm">Total Pedidos</h3>
          <p className="text-3xl font-bold text-white">{metrics.pedidosTotal}</p>
          <span className="text-gray-500 text-sm font-bold mt-2 block">Ticket Médio: R$ {(metrics.faturacaoBruta / metrics.pedidosTotal).toFixed(2)}</span>
        </div>
      </div>
    </div>
  );
}