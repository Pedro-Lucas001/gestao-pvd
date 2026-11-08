import { test } from "node:test";
import assert from "node:assert/strict";
import {
  cents,
  emptyDraft,
  oneRecord,
  orderPayload,
  toggleModifier,
  urgency,
} from "../src/lib/operations.js";
import { canAccess } from "../src/auth/permissions.js";
import { accessModules } from "../src/auth/modules.js";
import { filterMenu, publicProducts } from "../src/public/menuData.js";

test("every internal module follows the same least-privilege role matrix", () => {
  const expected = {
    admin: accessModules.filter((m) => m.path !== "/funcionario").map((m) => m.path),
    cashier: ["/funcionario", "/pedidos-online", "/pdv", "/atendimento"],
    kitchen: ["/funcionario", "/cozinha"],
  };
  for (const role of [
    "admin",
    "cashier",
    "kitchen",
    null,
    "customer",
    "owner",
    "",
  ]) {
    const actual = accessModules
      .filter((m) => canAccess(role, m.roles))
      .map((m) => m.path);
    assert.deepEqual(actual, expected[role] || []);
  }
  assert.equal(canAccess("cashier"), false);
});

test("public catalog projects presentation fields and rejects invalid prices", () => {
  const item = {
    id: "burger",
    name: "Hambúrguer",
    category: "hamburgueres",
    price_cents: 1700,
    description: "Pão e carne",
    image_path: "/menu/hamburgueres.svg",
    unit_cost_cents: 500,
    stock: 10,
    customer_phone: "private-fixture",
    sector: "grill",
    allowed_modifiers: ["Sem cebola"],
  };
  assert.deepEqual(
    Object.keys(publicProducts([item])[0]).sort(),
    [
      "id",
      "name",
      "category",
      "description",
      "price_cents",
      "image_path",
    ].sort(),
  );
  for (const price_cents of [-1, 0, 1.5, "1700", NaN, null]) {
    assert.throws(() => publicProducts([{ ...item, price_cents }]));
  }
  assert.throws(() => publicProducts(null));
});

test("public menu search ignores accents and combines category with ingredients", () => {
  const products = [
    {
      id: "burger",
      name: "Hambúrguer",
      category: "hamburgueres",
      description: "Pão e queijo",
    },
    {
      id: "pastel",
      name: "Frango com queijo",
      category: "pasteis",
      description: "Pastel crocante",
    },
  ];
  assert.deepEqual(
    filterMenu(products, "all", " hamburguer ").map((p) => p.id),
    ["burger"],
  );
  assert.deepEqual(
    filterMenu(products, "pasteis", "QUEIJO").map((p) => p.id),
    ["pastel"],
  );
  assert.deepEqual(filterMenu(products, "all", "inexistente"), []);
});
test("currency parsing rejects ambiguous values and uses exact cents", () => {
  assert.equal(cents("19,90"), 1990);
  assert.equal(cents("0.05"), 5);
  assert.equal(cents("100"), 10000);
  for (const invalid of [
    "1.234,56",
    "1e3",
    "-1",
    "1.999",
    "NaN",
    "",
    "2,3,4",
  ]) {
    assert.throws(() => cents(invalid));
  }
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
test("KDS colors follow 10/20-minute bands without marking future tickets late", () => {
  const now = Date.parse("2026-11-05T18:00:00Z");
  assert.equal(urgency("2026-11-05T17:50:01Z", now), "normal");
  assert.equal(urgency("2026-11-05T17:50:00Z", now), "warning");
  assert.equal(urgency("2026-11-05T17:40:00Z", now), "warning");
  assert.equal(urgency("2026-11-05T17:39:59Z", now), "critical");
  assert.equal(urgency("2026-11-05T18:05:00Z", now), "normal");
});
test("route guards deny finance/admin routes to all staff roles", () => {
  for (const role of ["cashier", "kitchen", null, "owner"]) {
    assert.equal(canAccess(role, ["admin"]), false);
  }
  assert.equal(canAccess("admin", ["admin"]), true);
  assert.equal(canAccess("kitchen", ["admin", "cashier"]), false);
  assert.equal(canAccess("cashier", ["admin", "kitchen"]), false);
});

test("RPC composite accepts object or a single-row response and rejects ambiguity", () => {
  assert.deepEqual(oneRecord([{ id: "order-1" }]), { id: "order-1" });
  assert.deepEqual(oneRecord({ id: "order-1" }), { id: "order-1" });
  for (const invalid of [null, [], [{}, {}], {}]) {
    assert.throws(() => oneRecord(invalid));
  }
});

test("inactivity locks at ten minutes even when a wall clock moves backwards", async () => {
  const { expiredActivity, IDLE_LIMIT_MS } =
    await import("../src/auth/useIdleLock.js");
  assert.equal(IDLE_LIMIT_MS, 600000);
  assert.equal(expiredActivity(1000, 100, 600999, 600099), false);
  assert.equal(expiredActivity(1000, 100, 601000, 600100), true);
  assert.equal(expiredActivity(1000, 100, -1000, 600100), true);
});

test("network timeout aborts a waiting request without discarding auth headers", async () => {
  const { fetchWithTimeout } = await import("../src/lib/network.js");
  let captured;
  const transport = (_url, init) =>
    new Promise((_resolve, reject) => {
      captured = init;
      init.signal.addEventListener(
        "abort",
        () => reject(new Error("TEST_TIMEOUT")),
        { once: true },
      );
    });
  await assert.rejects(
    fetchWithTimeout(
      "https://example.test",
      { headers: { Authorization: "test-fixture-only" } },
      transport,
      5,
    ),
    /TEST_TIMEOUT/,
  );
  assert.equal(captured.headers.Authorization, "test-fixture-only");
  assert.equal(captured.signal.aborted, true);
});

test("station estimates use backlog, measured prep time and capacity, with alert strictly above limit", async () => {
  const { calculateDemand } = await import("../src/kds/demand.js");
  const base = {
    queued_items: 15,
    preparing_items: 0,
    average_unit_seconds: 180,
    parallel_capacity: 3,
    critical_items: 15,
  };
  const normal = calculateDemand(base),
    busy = calculateDemand({ ...base, queued_items: 16 });
  assert.equal(normal.high, false);
  assert.equal(busy.high, true);
  assert.equal(busy.items, 16);
  assert.equal(busy.nextItemMinutes, 17);
  assert.ok(busy.nextItemMinutes > normal.nextItemMinutes);
  assert.ok(
    calculateDemand({ ...base, preparing_items: 5 }).nextItemMinutes >
      normal.nextItemMinutes,
  );
  assert.ok(
    calculateDemand({ ...base, parallel_capacity: 6 }).nextItemMinutes <
      normal.nextItemMinutes,
  );
  assert.equal(calculateDemand({ ...base, queued_items: 0 }).waitMinutes, 0);
  assert.ok(
    Number.isFinite(
      calculateDemand({
        queued_items: "bad",
        average_unit_seconds: NaN,
        parallel_capacity: 0,
      }).nextItemMinutes,
    ),
  );
});
test("landing pages are selected by verified operator role", async () => {
  const { homeForRole } = await import("../src/auth/permissions.js");
  assert.equal(homeForRole("admin"), "/dashboard");
  assert.equal(homeForRole("cashier"), "/funcionario");
  assert.equal(homeForRole("kitchen"), "/funcionario");
  assert.equal(homeForRole(null), "/login");
  assert.equal(homeForRole("customer"), "/login");
});

test("order prediction follows the slowest required station and responds to cart quantities", async () => {
  const { estimateOrderPreparation } = await import("../src/kds/demand.js");
  const stations = [
    {
      sector: "grill",
      queued_items: 18,
      preparing_items: 0,
      average_unit_seconds: 180,
      parallel_capacity: 3,
      critical_items: 15,
    },
    {
      sector: "bar",
      queued_items: 0,
      preparing_items: 0,
      average_unit_seconds: 60,
      parallel_capacity: 3,
      critical_items: 20,
    },
  ];
  assert.equal(
    estimateOrderPreparation(stations, [
      {
        id: "burger",
        sector: "grill",
        quantity: 2,
      },
      { id: "drink", sector: "bar", quantity: 4 },
    ]),
    20,
  );
  assert.equal(
    estimateOrderPreparation(stations, [{ sector: "grill", quantity: 8 }]),
    26,
  );
  assert.equal(
    estimateOrderPreparation(stations, [{ sector: "bar", quantity: 4 }]),
    2,
  );
  assert.equal(
    estimateOrderPreparation(stations, [{ id: "unknown", quantity: 1 }]),
    null,
  );
  assert.equal(
    estimateOrderPreparation([], [{ sector: "bar", quantity: 1 }]),
    null,
  );
});

test("an empty station never promises less than one item's preparation average", async () => {
  const { calculateDemand, estimateOrderPreparation } =
    await import("../src/kds/demand.js");
  const station = {
    sector: "grill",
    queued_items: 0,
    preparing_items: 0,
    average_unit_seconds: 180,
    parallel_capacity: 3,
    critical_items: 15,
  };
  assert.equal(calculateDemand(station).nextItemMinutes, 3);
  assert.equal(
    estimateOrderPreparation([station], [{ sector: "grill", quantity: 1 }]),
    3,
  );
});

test("customer cart strips client prices and preserves line customizations", async () => {
  const { cartPayload, draftLine, patchCart, trackingToken } = await import("../src/public/cart.js");
  const item = { ...draftLine({ id: "burger", name: "Burger", price_cents: 1 }), modifiers: ["Sem cebola"], notes: "Bem quente" };
  assert.deepEqual(cartPayload([item]), [{ product_id: "burger", quantity: 1, modifiers: ["Sem cebola"], notes: "Bem quente" }]);
  assert.equal(patchCart([item], item.line_id, { quantity: 0 }).length, 0);
  assert.equal(patchCart([item], item.line_id, { quantity: 100 })[0].quantity, 100);
  assert.match(trackingToken(), /^[a-f0-9]{64}$/);
  assert.notEqual(trackingToken(), trackingToken());
});

test("product images accept managed paths and raster signatures only", async () => {
  const { productImageUrl, imageFileType } = await import("../src/lib/productImages.js");
  const path="/storage/v1/object/public/planeta-product-images/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.webp";
  assert.equal(productImageUrl(path,"https://fixture.supabase.co"),`https://fixture.supabase.co${path}`);
  assert.equal(productImageUrl("/menu/bebidas.svg"),"/menu/bebidas.svg");
  for(const p of ["https://attacker.test/pixel.png","javascript:alert(1)","/storage/v1/object/public/private/secret.png","//attacker.test/x","/menu/../../secret.svg"]) assert.equal(productImageUrl(p,"https://fixture.supabase.co"),"");
  assert.equal(imageFileType(new Uint8Array([137,80,78,71,13,10,26,10])),"image/png");
  assert.equal(imageFileType(new Uint8Array([255,216,255,0])),"image/jpeg");
  assert.equal(imageFileType(new TextEncoder().encode('<svg onload="bad"/>')) ,"");
});

test("delivery receipt highlights terminal, pending money, reference and exact card fee", async () => {
  const { receiptText } = await import("../scripts/print-agent/receipt.mjs");
  const receipt = receiptText({ number: 7, revision: 1, created_at: "2026-11-08T20:00:00Z", fulfillment: "delivery", items: [{ name: "Burger", quantity: 1, unit_price_cents: 1000, modifiers: [], notes: "Sem cebola\u001b\u000c" }], subtotal_cents: 1000, delivery_fee_cents: 100, card_fee_cents: 66, total_cents: 1166, paid_cents: 0, due_cents: 1166, payment_method: "card_delivery", contact: { name: "Cliente", phone: "5581999999999", address: "Rua 123", reference: "Farmacia" } });
  assert.match(receipt, /LEVAR MAQUINETA/);
  assert.match(receipt, /PAGAMENTO PENDENTE/);
  assert.match(receipt, /6%/);
  assert.match(receipt, /11,66/);
  assert.match(receipt, /Referencia: Farmacia/);
  assert.equal(receipt.includes(String.fromCharCode(27)), false);
  assert.equal(receipt.includes(String.fromCharCode(12)), false);
  assert.ok(receipt.split("\n").every((line) => line.length <= 42));
});

test("cash receipt separates tender and change from revenue", async () => {
  const { receiptText } = await import("../scripts/print-agent/receipt.mjs");
  const base = { number: 8, revision: 1, created_at: "2026-11-08T20:00:00Z", fulfillment: "delivery", items: [], subtotal_cents: 1000, delivery_fee_cents: 100, card_fee_cents: 0, total_cents: 1100, paid_cents: 0, due_cents: 1100, payment_method: "cash", cash_change_for_cents: 2000, contact: {} };
  assert.match(receiptText(base), /Levar troco: R\$\s*9,00/);
  assert.match(receiptText({ ...base, cash_change_for_cents: null }), /sem troco/);
  assert.match(receiptText({ ...base, reprint: true }), /SEGUNDA VIA/);
});
