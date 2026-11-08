export default function OrderProgress({ order, labels }) {
  const steps = [
    ["accepted", "Na fila da cozinha"],
    ["preparing", "Em preparo"],
    ["ready", "Pronto"],
    ...(order.fulfillment === "delivery" ? [["dispatched", "Saiu para entrega"]] : []),
    ["completed", order.fulfillment === "delivery" ? "Entregue" : "Retirado"],
  ];
  const current = steps.findIndex(([status]) => status === order.status);
  return <section className="customer-progress customer-panel" aria-label="Andamento do pedido" aria-live="polite">
    <h2>Do preparo até você</h2>
    {order.status === "cancelled" ? <p>Pedido cancelado. Consulte o pagamento abaixo e fale com a equipe.</p> : <ol className="customer-milestones">
      {steps.map(([status, label], index) => <li key={status} data-done={current >= index} aria-current={order.status === status ? "step" : undefined}>
        <span aria-hidden="true">{current > index ? "✓" : index + 1}</span><strong>{label}</strong>
      </li>)}
    </ol>}
    <p>{order.updated_at && `Última mudança: ${new Date(order.updated_at).toLocaleString("pt-BR")}. `}As etapas são atualizadas pela equipe; não há rastreamento por GPS.</p>
    {order.history?.length > 0 && <details><summary>Histórico do pedido</summary><ol className="customer-history">
      {order.history.map((event, index) => <li key={index}><strong>{labels[event.status] || event.status}</strong> · <time dateTime={event.at}>{new Date(event.at).toLocaleString("pt-BR")}</time></li>)}
    </ol></details>}
  </section>;
}
