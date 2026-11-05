import { readLimited } from "./http.ts";
import { gateway } from "./gateway.ts";
Deno.test(
  "raw webhook body remains byte-identical for signature validation",
  async () => {
    const input = new Uint8Array([0, 32, 123, 125, 255]);
    const output = await readLimited(
      new Request("http://localhost", { method: "POST", body: input }),
      5,
    );
    if (
      output.length !== input.length ||
      !input.every((value, index) => value === output[index])
    )
      throw new Error("Body changed");
  },
);
Deno.test(
  "chunked input is rejected above the limit, even without Content-Length",
  async () => {
    let rejected = false;
    try {
      await readLimited(
        new Request("http://localhost", {
          method: "POST",
          body: new Uint8Array(11),
        }),
        10,
      );
    } catch (error) {
      rejected = error instanceof RangeError;
    }
    if (!rejected) throw new Error("Oversized input was accepted");
  },
);
Deno.test(
  "gateway is unavailable rather than fabricating approval or a PIX",
  () => {
    try {
      gateway();
    } catch (error) {
      if (
        error instanceof Error &&
        error.message === "PAYMENT_GATEWAY_NOT_CONFIGURED"
      )
        return;
    }
    throw new Error("Gateway must fail closed");
  },
);
