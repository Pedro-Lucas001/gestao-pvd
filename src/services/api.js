const API_URL = 'http://localhost:3000/api';

export async function fecharCaixa(turnoId, saldoFinal) {
    const res = await fetch(`${API_URL}/caixa/fechar`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ turno_id: turnoId, saldo_final: saldoFinal })
    });
    return res.json();
}

export async function getHistoricoTurnos() {
    const res = await fetch(`${API_URL}/caixa/turnos`);
    return res.json();
}

export async function criarProduto(dadosProduto) {
    const res = await fetch(`${API_URL}/produtos`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(dadosProduto)
    });
    return res.json();
}

export async function getPedidos() {
    const res = await fetch(`${API_URL}/pedidos`);
    return res.json();
}

export async function atualizarStatusPedido(id, status) {
    const res = await fetch(`${API_URL}/pedidos/${id}/status`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status })
    });
    return res.json();
}

export async function getProdutos() {
    const res = await fetch(`${API_URL}/produtos`);
    return res.json();
}

export async function criarPedido(dadosPedido) {
    const res = await fetch(`${API_URL}/pedidos`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(dadosPedido)
    });
    return res.json();
}

export async function getStatusCaixa() {
    const res = await fetch(`${API_URL}/caixa/status`);
    return res.json();
}

export async function abrirCaixa(saldoInicial) {
    const res = await fetch(`${API_URL}/caixa/abrir`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ saldo_inicial: saldoInicial })
    });
    return res.json();
    
}