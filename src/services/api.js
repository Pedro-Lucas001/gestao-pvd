let csrf = "";
export function setCsrf(value) {
  csrf = value || "";
}
export async function request(path, body, signal) {
  const response = await fetch(`/api/${path}`, {
    method: body === undefined ? "GET" : "POST",
    headers: { "Content-Type": "application/json", "X-CSRF-Token": csrf },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal,
  });
  const data = await response.json();
  if (!response.ok) {
    const error = new Error(
      data.error || "Não foi possível concluir a operação.",
    );
    error.status = response.status;
    throw error;
  }
  return data;
}
