import { test } from "node:test";
import assert from "node:assert/strict";
import {
  oneRecord,
  cents,
  urgency,
  toggleModifier,
  emptyDraft,
  orderPayload,
} from "../src/lib/operations.js";
import { canAccess } from "../src/auth/permissions.js";
test("currency parsing rejects ambiguous values and uses exact cents", () => {
  assert.equal(cents("19,90"), 1990);
  assert.equal(cents("0.05"), 5);
  assert.equal(cents("100"), 10000);
  for (const invalid of ["1.234,56", "1e3", "-1", "1.999", "NaN", "", "2,3,4"])
    assert.throws(() => cents(invalid));
});
test("item temperatures are mutually exclusive without removing exclusions", () => {
  assert.deepEqual(
    toggleModifier(["Sem cebola", "Ponto: ao ponto"], "Ponto: bem passado"),
    ["Sem cebola", "Ponto: bem passado"],
  );
  assert.deepEqual(toggleModifier(["Sem cebola"], "Sem cebola"), []);
});
test("retry preserves operation key and never sends a client-controlled price", () => {
  const draft = {
    ...emptyDraft(),
    customer: " Mesa 4 ",
    items: [
      {
        id: "x-tudo",
        quantity: 2,
        price_cents: 1,
        modifiers: ["Sem cebola"],
        notes: "Sem gelo",
      },
    ],
  };
  const first = orderPayload(draft),
    second = orderPayload(JSON.parse(JSON.stringify(draft)));
  assert.deepEqual(first, second);
  assert.equal(first.p_customer, "Mesa 4");
  assert.equal(first.p_items[0].unit_price_cents, undefined);
  assert.equal(first.p_items[0].price_cents, undefined);
  assert.notEqual(draft.key, emptyDraft().key);
  assert.equal(new Set(Object.values(draft.paymentKeys)).size, 3);
});
test("KDS thresholds are deterministic and handle clock skew", () => {
  const now = Date.parse("2026-11-05T18:00:00Z");
  assert.equal(urgency("2026-11-05T17:52:01Z", now), "normal");
  assert.equal(urgency("2026-11-05T17:52:00Z", now), "warning");
  assert.equal(urgency("2026-11-05T17:45:00Z", now), "critical");
  assert.equal(urgency("2026-11-05T18:05:00Z", now), "normal");
});
test("route guards deny finance/admin routes to all staff roles", () => {
  for (const role of ["cashier", "kitchen", null, "owner"])
    assert.equal(canAccess(role, ["admin"]), false);
  assert.equal(canAccess("admin", ["admin"]), true);
  assert.equal(canAccess("kitchen", ["admin", "cashier"]), false);
  assert.equal(canAccess("cashier", ["admin", "kitchen"]), false);
});

test("RPC composite accepts object or a single-row response and rejects ambiguity", () => {
  assert.deepEqual(oneRecord([{ id: "order-1" }]), { id: "order-1" });
  assert.deepEqual(oneRecord({ id: "order-1" }), { id: "order-1" });
  for (const invalid of [null, [], [{}, {}], {}])
    assert.throws(() => oneRecord(invalid));
});
