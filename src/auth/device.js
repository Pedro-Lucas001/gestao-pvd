const deviceKey = "planeta:registered-terminal:v1";
export function deviceToken() {
  try {
    return localStorage.getItem(deviceKey) || "";
  } catch {
    return "";
  }
}
export function rememberDevice(token) {
  if (typeof token !== "string" || !/^[a-f0-9]{64}$/.test(token))
    throw new Error("Resposta de cadastro do terminal inválida.");
  localStorage.setItem(deviceKey, token);
}
