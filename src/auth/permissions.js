export function canAccess(role, allowed = []) {
  return (
    ["admin", "cashier", "kitchen"].includes(role) && allowed.includes(role)
  );
}

export function homeForRole(role) {
  return role === "admin"
    ? "/dashboard"
    : role === "kitchen"
      ? "/cozinha"
      : role === "cashier"
        ? "/pdv"
        : "/login";
}
