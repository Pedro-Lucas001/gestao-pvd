import { money, toggleModifier } from "../lib/operations";
import {
  industrialMeatNotice,
  sandwichCategories,
  visibleModifiers,
} from "./menuOptions";

export default function ProductOptions({
  product,
  line,
  onChange,
  catalog,
  disabled = false,
}) {
  const modifiers = visibleModifiers(product),
    sandwich = sandwichCategories.includes(product?.category);
  const addons = sandwich
    ? catalog.filter((p) => p.category === "adicionais")
    : [];
  function toggleAddon(extra) {
    const id = extra.product_id || extra.id;
    onChange({
      addons: line.addons?.includes(id)
        ? line.addons.filter((value) => value !== id)
        : [...(line.addons || []), id],
      addon_prices: [
        ...(line.addon_prices || []).filter((p) => p.product_id !== id),
        { product_id: id, name: extra.name, price_cents: extra.price_cents },
      ],
    });
  }
  return (
    <div className="customer-product-options">
      {sandwich && <p className="customer-meat-note">{industrialMeatNotice}</p>}
      {product?.category === "coxinhas" ? (
        <fieldset disabled={disabled} className="customer-option-group">
          <legend>Escolha o sabor das mini coxinhas</legend>
          {modifiers
            .filter((m) => m.startsWith("Sabor:"))
            .map((m) => (
              <label className="customer-checkbox" key={m}>
                <input
                  type="radio"
                  required
                  name={`flavor-${line.line_id}`}
                  checked={line.modifiers.includes(m)}
                  onChange={() =>
                    onChange({
                      modifiers: [
                        ...line.modifiers.filter(
                          (v) => !v.startsWith("Sabor:"),
                        ),
                        m,
                      ],
                    })
                  }
                />
                {m === "Sabor: Mistas"
                  ? "Mistas / misturadas (sabores disponíveis)"
                  : m.slice(7)}
              </label>
            ))}
          {!modifiers.some((m) => m.startsWith("Sabor:")) && (
            <p role="alert">Mini coxinhas indisponíveis hoje.</p>
          )}
          {line.modifiers
            .filter((m) => m.startsWith("Sabor:"))
            .some((m) => !modifiers.includes(m)) && (
            <p role="alert">
              Esse sabor ficou indisponível. Escolha outro sabor.
            </p>
          )}
        </fieldset>
      ) : (
        modifiers.length > 0 && (
          <fieldset disabled={disabled} className="customer-option-group">
            <legend>
              {product?.category === "pasteis"
                ? "Acompanhamentos do pastel"
                : "Personalize seu lanche"}
            </legend>
            {product?.category === "pasteis" && (
              <p>
                Marque o que deseja incluir. Desmarcado significa sem esse
                acompanhamento.
              </p>
            )}
            {modifiers.map((m) => (
              <label key={m} className="customer-checkbox">
                <input
                  type="checkbox"
                  checked={line.modifiers.includes(m)}
                  onChange={() =>
                    onChange({ modifiers: toggleModifier(line.modifiers, m) })
                  }
                />
                {product?.category === "pasteis" ? m.replace(/^Com /, "") : m}
              </label>
            ))}
          </fieldset>
        )
      )}
      {sandwich && (
        <fieldset disabled={disabled} className="customer-option-group">
          <legend>Adicionais para este lanche</legend>
          <p>
            Uma unidade de cada adicional selecionado por lanche. O preço será
            somado ao pedido.
          </p>
          {addons.map((extra) => (
            <label
              className="customer-checkbox"
              key={extra.product_id || extra.id}
            >
              <input
                type="checkbox"
                checked={
                  line.addons?.includes(extra.product_id || extra.id) || false
                }
                onChange={() => toggleAddon(extra)}
              />
              {extra.name}
              <strong>+ {money(extra.price_cents)}</strong>
            </label>
          ))}
          {!addons.length && <p>Nenhum adicional disponível no momento.</p>}
          {(line.addons || [])
            .filter((id) => !addons.some((p) => (p.product_id || p.id) === id))
            .map((id) => (
              <label key={id} className="customer-checkbox">
                <input
                  type="checkbox"
                  checked
                  onChange={() =>
                    onChange({
                      addons: line.addons.filter((value) => value !== id),
                    })
                  }
                />
                Adicional indisponível:{" "}
                {line.addon_prices?.find((p) => p.product_id === id)?.name ||
                  id}
                . Desmarque para continuar.
              </label>
            ))}
        </fieldset>
      )}
    </div>
  );
}
