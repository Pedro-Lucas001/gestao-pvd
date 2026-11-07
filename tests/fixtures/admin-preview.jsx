// Fixture de revisão visual. Não é entrada do build e não autentica usuário.
import { useState } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { DashboardView } from "../../src/admin/AdminDashboard";
import { ProductEditor } from "../../src/admin/Catalog";
import { StaffHomeView } from "../../src/auth/StaffHome";
import "../../src/index.css";
import "../../src/App.css";
const p = {
  from: "2026-11-07",
  to: "2026-11-07",
  received_cents: 42000,
  refunds_cents: 2000,
  net_received_cents: 40000,
  cost_cents: 12500,
  expenses_cents: 3000,
  result_cents: 24500,
  incomplete_cost_orders: 0,
  paid_orders: 18,
  pos_received_cents: 26000,
  online_received_cents: 16000,
};
const data = {
  reference_date: "2026-11-07",
  periods: {
    day: p,
    week: {
      ...p,
      from: "2026-11-02",
      received_cents: 215000,
      pos_received_cents: 133000,
      online_received_cents: 82000,
      paid_orders: 100,
      net_received_cents: 213000,
      cost_cents: 64500,
      result_cents: 145500,
    },
    month: {
      ...p,
      from: "2026-11-01",
      received_cents: 233000,
      pos_received_cents: 145000,
      online_received_cents: 88000,
      paid_orders: 110,
      net_received_cents: 231000,
      cost_cents: 69900,
      result_cents: 158100,
    },
  },
  daily: [18000, 34000, 24000, 49000, 29000, 37000, 42000].map((n, i) => ({
    date: `2026-11-0${i + 1}`,
    received_cents: n,
    refunds_cents: i === 6 ? 2000 : 0,
  })),
  inventory: {
    count: 4,
    low_count: 2,
    negative_count: 1,
    value_cents: 87950,
    items: [
      {
        id: "1",
        name: "Pão de hambúrguer",
        unit: "un",
        stock: 18,
        minimum_stock: 30,
      },
      { id: "2", name: "Queijo", unit: "g", stock: -100, minimum_stock: 1000 },
      {
        id: "3",
        name: "Carne de hambúrguer",
        unit: "un",
        stock: 45,
        minimum_stock: 20,
      },
      { id: "4", name: "Óleo", unit: "ml", stock: 6000, minimum_stock: 3000 },
    ],
  },
  open_shifts: 1,
  receivable_cents: 6200,
};
export default function Preview() {
  const [tab, setTab] = useState("dashboard"),
    [period, setPeriod] = useState("day"),
    [reference, setReference] = useState("2026-11-07"),
    [result, setResult] = useState("");
  return (
    <BrowserRouter>
      <main className="main-content">
        <p className="control-notice">
          PRÉVIA DE TESTE — valores fictícios, sem conexão com banco ou contas
          da loja.
        </p>
        <nav className="control-shortcuts">
          {[
            ["dashboard", "Dashboard"],
            ["product", "Formulário de produto"],
            ["cashier", "Funcionário caixa"],
            ["kitchen", "Funcionário cozinha"],
          ].map(([id, label]) => (
            <button key={id} className="secondary" onClick={() => setTab(id)}>
              {label}
            </button>
          ))}
        </nav>
        {tab === "dashboard" ? (
          <DashboardView
            {...{ data, reference, setReference, period, setPeriod }}
            refresh={() => {}}
            busy={false}
            error=""
          />
        ) : tab === "product" ? (
          <section className="management">
            <ProductEditor
              product={{
                id: "test-product",
                name: "Burger de teste",
                price_cents: 1990,
                category: "hamburgueres",
                sector: "grill",
                allowed_modifiers: ["Sem cebola"],
                active: true,
              }}
              allowUpload={false}
              busy={false}
              error=""
              onCancel={() => setTab("dashboard")}
              onSave={(p) =>
                setResult(
                  `Teste local: ${p.name}, ${p.price_cents} centavos, categoria ${p.category}. Nenhum dado foi enviado.`,
                )
              }
            />
            {result && (
              <p role="status" className="control-success">
                {result}
              </p>
            )}
          </section>
        ) : (
          <StaffHomeView
            profile={{
              name: "Funcionário de teste",
              role: tab,
              sector: tab === "kitchen" ? "grill" : null,
            }}
          />
        )}
      </main>
    </BrowserRouter>
  );
}
createRoot(document.getElementById("root")).render(<Preview />);
