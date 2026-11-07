export const PRODUCT_IMAGE_BUCKET = "planeta-product-images";
export const PRODUCT_IMAGE_PREFIX = `/storage/v1/object/public/${PRODUCT_IMAGE_BUCKET}/`;
export const MAX_PRODUCT_IMAGE_BYTES = 5 * 1024 * 1024;
export function productImageUrl(path, base) {
  if (typeof path !== "string") return "";
  if (/^\/menu\/[a-z-]+\.svg$/.test(path)) return path;
  if (!new RegExp(`^${PRODUCT_IMAGE_PREFIX}[a-f0-9-]{36}\\.webp$`).test(path))
    return "";
  try {
    const url = new URL(base);
    if (!(
      url.protocol === "https:" ||
      (url.protocol === "http:" &&
        ["localhost", "127.0.0.1"].includes(url.hostname))
    ))
      return "";
    return `${url.origin}${path}`;
  } catch {
    return "";
  }
}
export function imageFileType(bytes) {
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff)
    return "image/jpeg";
  if ([137, 80, 78, 71, 13, 10, 26, 10].every((n, i) => bytes[i] === n))
    return "image/png";
  const chars = (start, end) => String.fromCharCode(...bytes.slice(start, end));
  return chars(0, 4) === "RIFF" && chars(8, 12) === "WEBP" ? "image/webp" : "";
}
export async function prepareProductImage(file) {
  if (
    !file ||
    !["image/jpeg", "image/png", "image/webp"].includes(file.type) ||
    file.size > MAX_PRODUCT_IMAGE_BYTES ||
    file.size <= 0
  )
    throw new Error("Escolha uma foto JPG, PNG ou WebP de até 5 MB.");
  const type = imageFileType(
    new Uint8Array(await file.slice(0, 12).arrayBuffer()),
  );
  if (!type || type !== file.type)
    throw new Error(
      "O conteúdo do arquivo não corresponde a uma foto JPG, PNG ou WebP.",
    );
  const bitmap = await createImageBitmap(file);
  try {
    if (
      !bitmap.width ||
      !bitmap.height ||
      bitmap.width * bitmap.height > 40000000
    )
      throw new Error(
        "A foto é grande demais. Use uma imagem com até 40 megapixels.",
      );
    const scale = Math.min(1, 1600 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.round(bitmap.width * scale);
    canvas.height = Math.round(bitmap.height * scale);
    const context = canvas.getContext("2d");
    if (!context)
      throw new Error("Não foi possível preparar a foto neste navegador.");
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolve) =>
      canvas.toBlob(resolve, "image/webp", 0.85),
    );
    if (
      !blob ||
      blob.type !== "image/webp" ||
      blob.size > MAX_PRODUCT_IMAGE_BYTES
    )
      throw new Error(
        "Não foi possível converter a foto. Tente outro arquivo.",
      );
    return blob;
  } finally {
    bitmap.close();
  }
}
