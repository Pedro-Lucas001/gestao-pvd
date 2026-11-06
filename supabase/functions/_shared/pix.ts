/** Static EMV/BR Code with an exact amount. It is NOT an API Pix Cob and does
 * not expire or prove settlement. The bank account remains outside this app. */
export function crc16(text: string): string {
  let crc = 0xffff;
  for (const byte of new TextEncoder().encode(text)) {
    crc ^= byte << 8;
    for (let i = 0; i < 8; i++)
      crc = crc & 0x8000 ? (crc << 1) ^ 0x1021 : crc << 1;
    crc &= 0xffff;
  }
  return crc.toString(16).toUpperCase().padStart(4, "0");
}
function tlv(id: string, value: string): string {
  const size = new TextEncoder().encode(value).length;
  if (size > 99) throw new Error("PIX_FIELD_TOO_LONG");
  return id + String(size).padStart(2, "0") + value;
}
function label(value: string, max: number): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Za-z0-9 .-]/g, "")
    .trim()
    .toUpperCase()
    .slice(0, max);
}
export function brCode(input: {
  key: string;
  name: string;
  city: string;
  amountCents: number;
  txid: string;
}): string {
  if (
    !Number.isSafeInteger(input.amountCents) ||
    input.amountCents <= 0 ||
    input.amountCents > 2147483647
  )
    throw new Error("INVALID_PIX_AMOUNT");
  if (!/^[\x21-\x7e]{5,77}$/.test(input.key))
    throw new Error("INVALID_PIX_KEY");
  const name = label(input.name, 25),
    city = label(input.city, 15);
  if (!name || !city || !input.txid.match(/^[A-Za-z0-9]{1,25}$/))
    throw new Error("INVALID_PIX_MERCHANT");
  const amount = (input.amountCents / 100).toFixed(2);
  const body =
    tlv("00", "01") +
    tlv("01", "11") +
    tlv("26", tlv("00", "BR.GOV.BCB.PIX") + tlv("01", input.key)) +
    tlv("52", "0000") +
    tlv("53", "986") +
    tlv("54", amount) +
    tlv("58", "BR") +
    tlv("59", name) +
    tlv("60", city) +
    tlv("62", tlv("05", input.txid)) +
    "6304";
  return body + crc16(body);
}
