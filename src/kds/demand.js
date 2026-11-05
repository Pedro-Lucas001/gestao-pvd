export const STATIONS = [
  { id: "grill", label: "Chapa", itemLabel: "itens na chapa", icon: "flame" },
  {
    id: "fryer",
    label: "Fritadeira",
    itemLabel: "porções na fila",
    icon: "cooking",
  },
  { id: "bar", label: "Bebidas", itemLabel: "bebidas na fila", icon: "cup" },
];
// Estimativa de trabalho por unidade, dividida pela capacidade configurada.
// Inclui fila + preparo, sem prometer um prazo de entrega ou inventar deslocamento.
export function calculateDemand(row) {
  const finite = (value, fallback = 0) =>
    Number.isFinite(Number(value)) ? Number(value) : fallback;
  const queued = Math.max(0, finite(row.queued_items));
  const preparing = Math.max(0, finite(row.preparing_items));
  const average = Math.max(1, finite(row.average_unit_seconds, 180));
  const capacity = Math.max(1, finite(row.parallel_capacity, 1));
  const critical = Math.max(1, finite(row.critical_items, 15));
  const items = queued + preparing;
  return {
    ...row,
    queued,
    preparing,
    items,
    average,
    capacity,
    critical,
    high: items > critical,
    sampleCount: Math.max(0, finite(row.sample_count)),
    waitMinutes: Math.ceil(items * average / capacity / 60),
    nextItemMinutes: Math.max(
      1,
      Math.ceil(average / 60),
      Math.ceil((items + 1) * average / capacity / 60),
    ),
    loadPercent: Math.min(100, Math.round(items / critical * 100)),
  };
}
export function ticketUnits(ticket) {
  return (ticket.items || []).reduce(
    (sum, item) => sum + Math.max(0, Number(item.quantity) || 0),
    0,
  );
}

// O pedido só fica disponível quando sua praça mais lenta termina. O deslocamento
// da entrega é separado, pois não há dados de logística que permitam estimá-lo.
export function estimateOrderPreparation(stations, items, products = []) {
  if (!items.length || !stations.length) return null;
  const quantities = {};
  for (const item of items) {
    const sector = products.find((product) => product.id === item.id)?.sector ||
      item.sector;
    if (
      !STATIONS.some((station) => station.id === sector) ||
      !Number.isInteger(item.quantity) || item.quantity < 1
    ) return null;
    quantities[sector] = (quantities[sector] || 0) + item.quantity;
  }
  let minutes = 0;
  for (const [sector, quantity] of Object.entries(quantities)) {
    const station = stations.find((station) => station.sector === sector);
    if (!station) return null;
    const load = calculateDemand(station);
    minutes = Math.max(
      minutes,
      Math.ceil(load.average / 60),
      Math.ceil((load.items + quantity) * load.average / load.capacity / 60),
    );
  }
  return Math.max(1, minutes);
}
