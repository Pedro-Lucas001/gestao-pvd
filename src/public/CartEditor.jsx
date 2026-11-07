import { Plus, Minus, Trash2 } from "lucide-react";
import { money, toggleModifier } from "../lib/operations";
import { draftLine, patchCart } from "./cart";
export default function CartEditor({ items, setItems, catalog, disabled = false, allowAdd = false }) {
  return <div className="customer-cart-editor">
    {items.map((item) => {
      const product = catalog.find((p) => (p.product_id || p.id) === item.product_id);
      return <article className="customer-cart-line" key={item.line_id}>
        <div><h3>{item.name}</h3><strong>{money((product?.price_cents ?? item.price_cents) * item.quantity)}</strong></div>
        <div className="quantity-controls"><button type="button" disabled={disabled} aria-label={`Diminuir ${item.name}`} onClick={() => setItems((p) => patchCart(p, item.line_id, { quantity: item.quantity - 1 }))}><Minus size={16} /></button><span>{item.quantity}</span><button type="button" disabled={disabled || item.quantity >= 100} aria-label={`Aumentar ${item.name}`} onClick={() => setItems((p) => patchCart(p, item.line_id, { quantity: item.quantity + 1 }))}><Plus size={16} /></button><button type="button" disabled={disabled} aria-label={`Remover ${item.name}`} onClick={() => setItems((p) => p.filter((i) => i.line_id !== item.line_id))}><Trash2 size={16} /></button></div>
        {(product?.allowed_modifiers || []).length > 0 && <div className="customer-modifiers">{product.allowed_modifiers.map((modifier) => <button type="button" disabled={disabled} key={modifier} aria-pressed={item.modifiers.includes(modifier)} onClick={() => setItems((p) => patchCart(p, item.line_id, { modifiers: toggleModifier(item.modifiers, modifier) }))}>{modifier}</button>)}</div>}
        <label>Observações de {item.name}<textarea disabled={disabled} value={item.notes} maxLength={500} placeholder="Ex.: sem molhos. Não informe dados pessoais aqui." onChange={(e) => setItems((p) => patchCart(p, item.line_id, { notes: e.target.value }))} /></label>
      </article>;
    })}
    {allowAdd && <label>Adicionar outro produto<select disabled={disabled || items.length >= 30} value="" onChange={(e) => { const product = catalog.find((p) => p.product_id === e.target.value); if (product) setItems((p) => [...p, draftLine(product)]); }}><option value="">Selecione uma opção</option>{catalog.map((p) => <option key={p.product_id} value={p.product_id}>{p.name} · {money(p.price_cents)}</option>)}</select></label>}
  </div>;
}
