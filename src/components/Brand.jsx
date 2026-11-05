import { Flame } from "lucide-react";
export default function Brand() {
  return (
    <div className="brand">
      <span className="brand-mark">
        <Flame size={23} />
      </span>
      <div>
        <strong>
          PLANETA<span>LANCHES</span>
        </strong>
        <small>GESTÃO & OPERAÇÃO</small>
      </div>
    </div>
  );
}
