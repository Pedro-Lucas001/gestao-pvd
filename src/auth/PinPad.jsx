import { Delete, RotateCcw } from "lucide-react";
export default function PinPad({
  value,
  onChange,
  disabled = false,
  id = "staff-pin",
}) {
  return (
    <div className="pin-pad">
      <label htmlFor={id}>PIN de 4 dígitos</label>
      <input
        id={id}
        className="pin-input pin-pad-display"
        aria-label="PIN de 4 dígitos"
        type="password"
        inputMode="none"
        pattern="[0-9]{4}"
        maxLength={4}
        minLength={4}
        required
        autoComplete="off"
        value={value}
        disabled={disabled}
        onChange={(event) =>
          onChange(event.target.value.replace(/\D/g, "").slice(0, 4))
        }
      />
      <span className="sr-only" aria-live="polite">
        {value.length} de 4 dígitos preenchidos
      </span>
      <div className="pin-numpad" aria-label="Teclado numérico">
        {[1, 2, 3, 4, 5, 6, 7, 8, 9].map((digit) => (
          <button
            type="button"
            key={digit}
            aria-label={`Dígito ${digit}`}
            disabled={disabled || value.length === 4}
            onClick={() => onChange(value + digit)}
          >
            {digit}
          </button>
        ))}
        <button
          type="button"
          className="pin-key-action"
          aria-label="Limpar PIN"
          disabled={disabled || !value.length}
          onClick={() => onChange("")}
        >
          <RotateCcw size={21} />
        </button>
        <button
          type="button"
          aria-label="Dígito 0"
          disabled={disabled || value.length === 4}
          onClick={() => onChange(value + "0")}
        >
          0
        </button>
        <button
          type="button"
          className="pin-key-action"
          aria-label="Apagar último dígito"
          disabled={disabled || !value.length}
          onClick={() => onChange(value.slice(0, -1))}
        >
          <Delete size={23} />
        </button>
      </div>
    </div>
  );
}
