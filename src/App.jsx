import { useState, useEffect } from 'react';
import { ShoppingCart, Trash2, Monitor, Utensils, DollarSign, Lock } from 'lucide-react';
import { getProdutos, criarPedido, getStatusCaixa, abrirCaixa, getPedidos, atualizarStatusPedido, criarProduto, fecharCaixa, getHistoricoTurnos } from './services/api';
import './App.css';

function App() {
  const [abaAtiva, setAbaAtiva] = useState('pdv'); // 'pdv', 'kds', 'produtos', 'caixa'
  const [produtos, setProdutos] = useState([]);
  const [carrinho, setCarrinho] = useState([]);
  const [clienteNome, setClienteNome] = useState('');
  const [tipoAtendimento, setTipoAtendimento] = useState('balcao');
  const [formaPagamento, setFormaPagamento] = useState('pix');
  const [caixaStatus, setCaixaStatus] = useState(null);
  const [saldoInicialInput, setSaldoInicialInput] = useState('');
  const [saldoFinalInput, setSaldoFinalInput] = useState('');
  const [historicoTurnos, setHistoricoTurnos] = useState([]);
  const [pedidosKDS, setPedidosKDS] = useState([]);

  // Estados para cadastro de novo produto
  const [novoNomeProd, setNovoNomeProd] = useState('');
  const [novoPrecoProd, setNovoPrecoProd] = useState('');

  useEffect(() => {
    carregarDados();
    if (abaAtiva === 'kds') {
      carregarPedidosKDS();
    }
    if (abaAtiva === 'caixa') {
      carregarHistoricoCaixa();
    }
  }, [abaAtiva]);

  async function carregarDados() {
    try {
      const prodData = await getProdutos();
      setProdutos(prodData);
      const caixaData = await getStatusCaixa();
      setCaixaStatus(caixaData);
    } catch (err) {
      console.error("Erro ao carregar dados:", err);
    }
  }

  async function carregarPedidosKDS() {
    try {
      const data = await getPedidos();
      setPedidosKDS(data);
    } catch (err) {
      console.error("Erro ao carregar pedidos KDS:", err);
    }
  }

  async function carregarHistoricoCaixa() {
    try {
      const data = await getHistoricoTurnos();
      setHistoricoTurnos(data);
    } catch (err) {
      console.error("Erro ao carregar histórico de caixa:", err);
    }
  }

  const adicionarAoCarrinho = (produto) => {
    const itemExistente = carrinho.find(item => item.id === produto.id);
    if (itemExistente) {
      setCarrinho(carrinho.map(item => 
        item.id === produto.id ? { ...item, quantidade: item.quantidade + 1 } : item
      ));
    } else {
      setCarrinho([...carrinho, { ...produto, quantidade: 1 }]);
    }
  };

  const removerDoCarrinho = (id) => {
    setCarrinho(carrinho.filter(item => item.id !== id));
  };

  const calcularTotal = () => {
    return carrinho.reduce((total, item) => total + (item.preco * item.quantidade), 0).toFixed(2);
  };

  const finalizarVenda = async () => {
    if (carrinho.length === 0) {
      alert("O carrinho está vazio!");
      return;
    }

    const dadosPedido = {
      cliente_nome: clienteNome || "Cliente Balcão",
      tipo_atendimento: tipoAtendimento,
      valor_total: parseFloat(calcularTotal()),
      forma_pagamento: formaPagamento,
      itens: carrinho.map(item => ({
        produto_id: item.id,
        quantidade: item.quantidade,
        preco_unitario: item.preco
      }))
    };

    try {
      const resposta = await criarPedido(dadosPedido);
      alert(resposta.message || "Pedido realizado com sucesso!");
      setCarrinho([]);
      setClienteNome('');
    } catch (err) {
      alert("Erro ao finalizar pedido: " + err.message);
    }
  };

  const handleAbrirCaixa = async () => {
    try {
      const res = await abrirCaixa(parseFloat(saldoInicialInput) || 0);
      alert(res.message);
      carregarDados();
    } catch (err) {
      alert("Erro ao abrir caixa: " + err.message);
    }
  };

  const handleFecharCaixa = async () => {
    if (!caixaStatus?.turno?.id) return;
    try {
      const res = await fecharCaixa(caixaStatus.turno.id, parseFloat(saldoFinalInput) || 0);
      alert(res.message);
      setSaldoFinalInput('');
      carregarDados();
      carregarHistoricoCaixa();
    } catch (err) {
      alert("Erro ao fechar caixa: " + err.message);
    }
  };

  const mudarStatusPedido = async (id, novoStatus) => {
    try {
      await atualizarStatusPedido(id, novoStatus);
      carregarPedidosKDS();
    } catch (err) {
      alert("Erro ao atualizar status: " + err.message);
    }
  };

  const handleCadastrarProduto = async (e) => {
    e.preventDefault();
    if (!novoNomeProd || !novoPrecoProd) {
      alert("Preencha o nome e o preço do produto!");
      return;
    }

    try {
      const res = await criarProduto({
        nome: novoNomeProd,
        preco: parseFloat(novoPrecoProd)
      });
      alert(res.message);
      setNovoNomeProd('');
      setNovoPrecoProd('');
      carregarDados();
    } catch (err) {
      alert("Erro ao cadastrar produto: " + err.message);
    }
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', background: '#121212', color: '#fff', fontFamily: 'sans-serif' }}>
      
      {/* Barra de Navegação Superior */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: '#1e1e1e', padding: '10px 20px', borderBottom: '1px solid #333' }}>
        <h2 style={{ color: '#ff5722', margin: 0, fontSize: '20px' }}>Gestão Operacional & PDV</h2>
        <div style={{ display: 'flex', gap: '10px' }}>
          <button 
            onClick={() => setAbaAtiva('pdv')}
            style={{ padding: '8px 16px', background: abaAtiva === 'pdv' ? '#ff5722' : '#2a2a2a', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}
          >
            <ShoppingCart size={16} style={{ verticalAlign: 'middle', marginRight: '5px' }} /> PDV
          </button>
          <button 
            onClick={() => setAbaAtiva('kds')}
            style={{ padding: '8px 16px', background: abaAtiva === 'kds' ? '#ff5722' : '#2a2a2a', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}
          >
            <Monitor size={16} style={{ verticalAlign: 'middle', marginRight: '5px' }} /> Cozinha
          </button>
          <button 
            onClick={() => setAbaAtiva('produtos')}
            style={{ padding: '8px 16px', background: abaAtiva === 'produtos' ? '#ff5722' : '#2a2a2a', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}
          >
            <Utensils size={16} style={{ verticalAlign: 'middle', marginRight: '5px' }} /> Cardápio
          </button>
          <button 
            onClick={() => setAbaAtiva('caixa')}
            style={{ padding: '8px 16px', background: abaAtiva === 'caixa' ? '#ff5722' : '#2a2a2a', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}
          >
            <DollarSign size={16} style={{ verticalAlign: 'middle', marginRight: '5px' }} /> Caixa
          </button>
        </div>
      </div>

      {/* Conteúdo Principal */}
      <div style={{ flex: 1, display: 'flex', overflow: 'hidden' }}>
        
        {/* ABA PDV */}
        {abaAtiva === 'pdv' && (
          caixaStatus && !caixaStatus.aberto ? (
            <div style={{ margin: 'auto', textAlign: 'center', background: '#1e1e1e', padding: '40px', borderRadius: '8px' }}>
              <h2>Caixa Fechado</h2>
              <p>Informe o saldo inicial para abrir o caixa:</p>
              <input 
                type="number" 
                placeholder="0.00" 
                value={saldoInicialInput} 
                onChange={(e) => setSaldoInicialInput(e.target.value)}
                style={{ padding: '10px', fontSize: '16px', marginRight: '10px', borderRadius: '4px', border: '1px solid #444', background: '#2a2a2a', color: '#fff' }}
              />
              <button 
                onClick={handleAbrirCaixa}
                style={{ padding: '10px 20px', background: '#ff5722', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}
              >
                Abrir Caixa
              </button>
            </div>
          ) : (
            <div style={{ display: 'flex', width: '100%', height: '100%' }}>
              <div style={{ flex: 2, padding: '20px', overflowY: 'auto', borderRight: '1px solid #222' }}>
                <h3>Produtos Disponíveis</h3>
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(180px, 1fr))', gap: '15px', marginTop: '15px' }}>
                  {produtos.map(prod => (
                    <div 
                      key={prod.id} 
                      onClick={() => adicionarAoCarrinho(prod)}
                      style={{ background: '#1e1e1e', padding: '15px', borderRadius: '8px', cursor: 'pointer', border: '1px solid #333' }}
                    >
                      <h4 style={{ margin: '0 0 10px 0' }}>{prod.nome}</h4>
                      <p style={{ color: '#ff5722', fontWeight: 'bold', margin: 0 }}>R$ {Number(prod.preco).toFixed(2)}</p>
                    </div>
                  ))}
                </div>
              </div>

              <div style={{ flex: 1, background: '#181818', padding: '20px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
                <div>
                  <h2>Carrinho de Compras</h2>
                  <div style={{ margin: '15px 0' }}>
                    <input 
                      type="text" 
                      placeholder="Nome do Cliente" 
                      value={clienteNome}
                      onChange={(e) => setClienteNome(e.target.value)}
                      style={{ width: '100%', padding: '10px', marginBottom: '10px', background: '#2a2a2a', border: '1px solid #444', color: '#fff', borderRadius: '4px' }}
                    />
                    <select 
                      value={tipoAtendimento} 
                      onChange={(e) => setTipoAtendimento(e.target.value)}
                      style={{ width: '100%', padding: '10px', marginBottom: '10px', background: '#2a2a2a', border: '1px solid #444', color: '#fff', borderRadius: '4px' }}
                    >
                      <option value="balcao">Balcão</option>
                      <option value="delivery">Delivery</option>
                      <option value="mesa">Mesa</option>
                    </select>
                    <select 
                      value={formaPagamento} 
                      onChange={(e) => setFormaPagamento(e.target.value)}
                      style={{ width: '100%', padding: '10px', background: '#2a2a2a', border: '1px solid #444', color: '#fff', borderRadius: '4px' }}
                    >
                      <option value="pix">PIX</option>
                      <option value="cartao_credito">Cartão de Crédito</option>
                      <option value="cartao_debito">Cartão de Débito</option>
                      <option value="dinheiro">Dinheiro</option>
                    </select>
                  </div>
                  <div style={{ maxHeight: '250px', overflowY: 'auto' }}>
                    {carrinho.length === 0 ? (
                      <p style={{ color: '#777', textAlign: 'center' }}>Carrinho vazio</p>
                    ) : (
                      carrinho.map(item => (
                        <div key={item.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px', background: '#222', padding: '8px', borderRadius: '4px' }}>
                          <div>
                            <span style={{ fontSize: '14px' }}>{item.nome}</span>
                            <div style={{ fontSize: '12px', color: '#aaa' }}>{item.quantidade}x R$ {Number(item.preco).toFixed(2)}</div>
                          </div>
                          <button onClick={() => removerDoCarrinho(item.id)} style={{ background: 'transparent', border: 'none', color: '#ff4444', cursor: 'pointer' }}>
                            <Trash2 size={16} />
                          </button>
                        </div>
                      ))
                    )}
                  </div>
                </div>
                <div>
                  <div style={{ borderTop: '1px solid #333', paddingTop: '15px', marginBottom: '15px', display: 'flex', justifyContent: 'space-between', fontSize: '18px', fontWeight: 'bold' }}>
                    <span>Total:</span>
                    <span style={{ color: '#4caf50' }}>R$ {calcularTotal()}</span>
                  </div>
                  <button 
                    onClick={finalizarVenda}
                    style={{ width: '100%', padding: '12px', background: '#4caf50', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold', fontSize: '16px' }}
                  >
                    Finalizar Venda
                  </button>
                </div>
              </div>
            </div>
          )
        )}

        {/* ABA KDS (COZINHA) */}
        {abaAtiva === 'kds' && (
          <div style={{ flex: 1, padding: '20px', overflowY: 'auto' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '20px' }}>
              <h2>Painel da Cozinha (KDS)</h2>
              <button 
                onClick={carregarPedidosKDS}
                style={{ padding: '8px 15px', background: '#333', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer' }}
              >
                Atualizar Pedidos
              </button>
            </div>

            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(280px, 1fr))', gap: '20px' }}>
              {pedidosKDS.map(pedido => (
                <div key={pedido.id} style={{ background: '#1e1e1e', border: '1px solid #333', borderRadius: '8px', padding: '15px', display: 'flex', flexDirection: 'column', justifyContent: 'space-between' }}>
                  <div>
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '10px', borderBottom: '1px solid #333', paddingBottom: '8px' }}>
                      <span style={{ fontWeight: 'bold', color: '#ff5722' }}>{pedido.cliente_nome}</span>
                      <span style={{ fontSize: '12px', background: '#333', padding: '2px 6px', borderRadius: '4px', textTransform: 'uppercase' }}>{pedido.tipo_atendimento}</span>
                    </div>
                    
                    <p style={{ fontSize: '12px', color: '#aaa', margin: '0 0 10px 0' }}>Status: <strong style={{ color: '#fff' }}>{pedido.status}</strong></p>

                    <ul style={{ paddingLeft: '18px', margin: '10px 0', color: '#ddd' }}>
                      {pedido.itens_pedido && pedido.itens_pedido.map(item => (
                        <li key={item.id} style={{ fontSize: '14px', marginBottom: '4px' }}>
                          {item.quantidade}x {item.produtos ? item.produtos.nome : 'Produto'}
                        </li>
                      ))}
                    </ul>
                  </div>

                  <div style={{ display: 'flex', gap: '5px', marginTop: '15px' }}>
                    {pedido.status === 'pendente' && (
                      <button 
                        onClick={() => mudarStatusPedido(pedido.id, 'preparando')}
                        style={{ flex: 1, padding: '8px', background: '#ff9800', color: '#000', border: 'none', borderRadius: '4px', fontWeight: 'bold', cursor: 'pointer' }}
                      >
                        Preparar
                      </button>
                    )}
                    {pedido.status === 'preparando' && (
                      <button 
                        onClick={() => mudarStatusPedido(pedido.id, 'pronto')}
                        style={{ flex: 1, padding: '8px', background: '#4caf50', color: '#fff', border: 'none', borderRadius: '4px', fontWeight: 'bold', cursor: 'pointer' }}
                      >
                        Pronto
                      </button>
                    )}
                    {pedido.status === 'pronto' && (
                      <button 
                        onClick={() => mudarStatusPedido(pedido.id, 'entregue')}
                        style={{ flex: 1, padding: '8px', background: '#2196f3', color: '#fff', border: 'none', borderRadius: '4px', fontWeight: 'bold', cursor: 'pointer' }}
                      >
                        Concluir
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ABA GESTÃO DE PRODUTOS (CARDÁPIO) */}
        {abaAtiva === 'produtos' && (
          <div style={{ flex: 1, padding: '20px', overflowY: 'auto', display: 'flex', gap: '30px' }}>
            <div style={{ flex: 1, background: '#1e1e1e', padding: '20px', borderRadius: '8px', border: '1px solid #333', height: 'fit-content' }}>
              <h3>Cadastrar Novo Produto</h3>
              <form onSubmit={handleCadastrarProduto} style={{ display: 'flex', flexDirection: 'column', gap: '15px', marginTop: '15px' }}>
                <div>
                  <label style={{ display: 'block', marginBottom: '5px', fontSize: '14px', color: '#aaa' }}>Nome do Produto</label>
                  <input 
                    type="text" 
                    placeholder="Ex: X-Burguer Especial" 
                    value={novoNomeProd}
                    onChange={(e) => setNovoNomeProd(e.target.value)}
                    style={{ width: '100%', padding: '10px', background: '#2a2a2a', border: '1px solid #444', color: '#fff', borderRadius: '4px' }}
                  />
                </div>
                <div>
                  <label style={{ display: 'block', marginBottom: '5px', fontSize: '14px', color: '#aaa' }}>Preço (R$)</label>
                  <input 
                    type="number" 
                    step="0.01" 
                    placeholder="0.00" 
                    value={novoPrecoProd}
                    onChange={(e) => setNovoPrecoProd(e.target.value)}
                    style={{ width: '100%', padding: '10px', background: '#2a2a2a', border: '1px solid #444', color: '#fff', borderRadius: '4px' }}
                  />
                </div>
                <button 
                  type="submit"
                  style={{ padding: '12px', background: '#ff5722', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}
                >
                  Salvar Produto
                </button>
              </form>
            </div>

            <div style={{ flex: 2, background: '#1e1e1e', padding: '20px', borderRadius: '8px', border: '1px solid #333' }}>
              <h3>Produtos Cadastrados no Cardápio</h3>
              <div style={{ marginTop: '15px', display: 'flex', flexDirection: 'column', gap: '10px', maxHeight: '450px', overflowY: 'auto' }}>
                {produtos.map(prod => (
                  <div key={prod.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: '#252525', padding: '12px 15px', borderRadius: '6px', border: '1px solid #333' }}>
                    <span style={{ fontWeight: '500' }}>{prod.nome}</span>
                    <span style={{ color: '#4caf50', fontWeight: 'bold' }}>R$ {Number(prod.preco).toFixed(2)}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* ABA GESTÃO DE CAIXA */}
        {abaAtiva === 'caixa' && (
          <div style={{ flex: 1, padding: '20px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '30px' }}>
            
            {/* Secção do Caixa Atual */}
            <div style={{ background: '#1e1e1e', padding: '20px', borderRadius: '8px', border: '1px solid #333' }}>
              <h3>Estado do Caixa Atual</h3>
              {caixaStatus && caixaStatus.aberto ? (
                <div style={{ marginTop: '15px', display: 'flex', flexDirection: 'column', gap: '15px' }}>
                  <div style={{ display: 'flex', gap: '20px' }}>
                    <p style={{ margin: 0 }}>Status: <strong style={{ color: '#4caf50' }}>ABERTO</strong></p>
                    <p style={{ margin: 0 }}>Saldo Inicial: <strong>R$ {Number(caixaStatus.turno.saldo_inicial).toFixed(2)}</strong></p>
                    <p style={{ margin: 0 }}>Aberto em: <strong>{new Date(caixaStatus.turno.aberto_em).toLocaleString()}</strong></p>
                  </div>
                  
                  <div style={{ display: 'flex', gap: '10px', alignItems: 'center', maxWidth: '400px', marginTop: '10px' }}>
                    <input 
                      type="number" 
                      step="0.01"
                      placeholder="Saldo Final (R$)" 
                      value={saldoFinalInput}
                      onChange={(e) => setSaldoFinalInput(e.target.value)}
                      style={{ padding: '10px', background: '#2a2a2a', border: '1px solid #444', color: '#fff', borderRadius: '4px', flex: 1 }}
                    />
                    <button 
                      onClick={handleFecharCaixa}
                      style={{ padding: '10px 20px', background: '#f44336', color: '#fff', border: 'none', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold' }}
                    >
                      Fechar Caixa
                    </button>
                  </div>
                </div>
              ) : (
                <p style={{ color: '#aaa', marginTop: '10px' }}>Não há nenhum caixa aberto no momento. Vá para a aba PDV para abrir um novo turno.</p>
              )}
            </div>

            {/* Histórico de Turnos */}
            <div style={{ background: '#1e1e1e', padding: '20px', borderRadius: '8px', border: '1px solid #333' }}>
              <h3>Histórico de Turnos de Caixa</h3>
              <div style={{ marginTop: '15px', display: 'flex', flexDirection: 'column', gap: '10px', maxHeight: '350px', overflowY: 'auto' }}>
                {historicoTurnos.map(turno => (
                  <div key={turno.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: '#252525', padding: '12px 15px', borderRadius: '6px', border: '1px solid #333' }}>
                    <div>
                      <span style={{ fontWeight: 'bold', textTransform: 'uppercase', color: turno.status === 'aberto' ? '#4caf50' : '#f44336' }}>
                        [{turno.status}]
                      </span>
                      <span style={{ marginLeft: '15px', fontSize: '14px', color: '#aaa' }}>
                        Aberto em: {new Date(turno.aberto_em).toLocaleString()}
                      </span>
                    </div>
                    <div style={{ display: 'flex', gap: '20px', fontSize: '14px' }}>
                      <span>Inicial: R$ {Number(turno.saldo_inicial).toFixed(2)}</span>
                      <span>Final: {turno.saldo_final ? `R$ ${Number(turno.saldo_final).toFixed(2)}` : '---'}</span>
                    </div>
                  </div>
                ))}
              </div>
            </div>

          </div>
        )}

      </div>
    </div>
  );
}

export default App;