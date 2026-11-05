import { CheckCheck, Clock3, Flame } from "lucide-react";
import { operationUI as ui } from "../design/operational";
import { STATIONS } from "./demand";
const edges = {
  normal: "pl:border-l-green-500",
  warning: "pl:border-l-yellow-400",
  critical: "pl:border-l-red-500",
};
const timeColors = {
  normal: "pl:text-green-400",
  warning: "pl:text-yellow-300",
  critical: "pl:text-red-400",
};
const labels = {
  normal: "No prazo",
  warning: "Atenção ao tempo",
  critical: "Acima de 20 min",
};
export default function OrderTicketCard(
  { ticket, urgency, now, busy, disabled, onAdvance },
) {
  const minutes = Math.max(
    0,
    Math.floor((now - Date.parse(ticket.created_at)) / 60000),
  );
  return (
    <article
      data-ticket={ticket.id}
      data-urgency={urgency}
      className={`kds-card ${urgency} pl:flex pl:min-w-0 pl:flex-col pl:rounded-xl pl:border pl:border-gray-700 pl:border-l-4 pl:bg-[#2d2d2d] pl:p-4 pl:text-gray-100 pl:shadow-sm pl:transition-colors ${
        edges[urgency]
      }`}
    >
      <header className="pl:flex pl:items-center pl:justify-between pl:gap-3">
        <h2 className="pl:m-0 pl:font-mono pl:text-2xl pl:font-bold pl:text-white">
          #{String(ticket.order_number).padStart(4, "0")}
        </h2>
        <span
          className={`pl:flex pl:shrink-0 pl:items-center pl:gap-2 pl:rounded-lg pl:bg-[#1a1a1a] pl:px-3 pl:py-2 pl:text-sm pl:font-bold ${
            timeColors[urgency]
          }`}
        >
          <Clock3 size={17} />
          {minutes} min
        </span>
      </header>
      <div className="pl:mt-4 pl:flex pl:items-center pl:justify-between pl:gap-3">
        <span className="pl:flex pl:items-center pl:gap-2 pl:text-sm pl:font-semibold pl:text-gray-200">
          <Flame size={17} className="pl:text-[#ff5722]" />
          {STATIONS.find((s) => s.id === ticket.sector)?.label}
        </span>
        <span className="pl:rounded-md pl:bg-[#1a1a1a] pl:px-3 pl:py-2 pl:text-xs pl:font-semibold pl:text-gray-300">
          {ticket.status === "queued" ? "Na fila" : "Em preparo"}
        </span>
      </div>
      <p className={`pl:mt-3 pl:text-xs pl:font-medium ${timeColors[urgency]}`}>
        {labels[urgency]}
      </p>
      <ul className="pl:my-4 pl:min-h-24 pl:flex-1 pl:list-none pl:space-y-3 pl:border-y pl:border-gray-700 pl:px-0 pl:py-4">
        {ticket.items.map((item, index) => (
          <li key={index} className="pl:flex pl:gap-3 pl:py-1">
            <strong className="pl:min-w-8 pl:text-xl pl:font-black pl:text-[#ff5722]">
              {item.quantity}x
            </strong>
            <div className="pl:min-w-0 pl:flex-1 pl:wrap-anywhere">
              <h3 className="pl:text-base pl:font-bold pl:text-gray-100">
                {item.name}
              </h3>
              {item.modifiers?.map((modifier) => (
                <p
                  key={modifier}
                  className="pl:mt-1 pl:text-xs pl:leading-5 pl:text-gray-400"
                >
                  − {modifier}
                </p>
              ))}
              {item.notes && (
                <p className="pl:mt-2 pl:text-sm pl:leading-5 pl:text-gray-300">
                  {item.notes}
                </p>
              )}
            </div>
          </li>
        ))}
      </ul>
      <button
        className={`${ui.action} pl:w-full`}
        disabled={disabled}
        onClick={() => onAdvance(ticket)}
      >
        {busy ? "Confirmando…" : ticket.status === "queued"
          ? (
            <>
              <Flame size={19} />Iniciar preparo
            </>
          )
          : (
            <>
              <CheckCheck size={19} />Pronto neste setor
            </>
          )}
      </button>
    </article>
  );
}
