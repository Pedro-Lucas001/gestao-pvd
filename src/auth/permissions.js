export function canAccess(role, allowed) {
  return (
    ["admin", "cashier", "kitchen"].includes(role) && allowed.includes(role)
  );
}
