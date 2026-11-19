// deno-lint-ignore-file no-explicit-any -- fixtures are untyped JSON
import { assert, assertEquals } from "@std/assert";
import {
  ConsentRequiredError,
  type Deps,
  handle,
  MAX_BODY_BYTES,
} from "./handler.ts";

const sections = JSON.parse(
  Deno.readTextFileSync(
    new URL("./fixtures/bodyspec_result.json", import.meta.url),
  ),
);

function fakeDeps(overrides: Partial<Deps> = {}) {
  const calls: { raw: any; scan: any }[] = [];
  const logs: Record<string, unknown>[] = [];
  const deps: Deps = {
    userIdFor: (jwt) => Promise.resolve(jwt === "good" ? "user-1" : null),
    featureEnabled: () => Promise.resolve(true),
    ingest: (_u, raw, scan) => {
      calls.push({ raw, scan });
      return Promise.resolve({ scan_id: "scan-1", status: "created" });
    },
    log: (e) => logs.push(e),
    now: () => new Date("2026-11-19T00:00:00Z"),
    ...overrides,
  };
  return { deps, calls, logs };
}

const post = (body: unknown, token = "good") =>
  new Request("http://localhost/ingest-scan", {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

const valid = {
  source: "bodyspec",
  provider_scan_id: "0f3c9a7e5b2d4c8a9e1f6b3d7a2c5e90",
  fetched_at: "2026-11-18T12:00:00Z",
  sections,
};

Deno.test("ingests a valid scan with identity stripped", async () => {
  const { deps, calls, logs } = fakeDeps();
  const res = await handle(post(valid), deps);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), {
    scan_id: "scan-1",
    status: "created",
    scan_status: "ok",
  });
  assertEquals(calls.length, 1);
  const { raw, scan } = calls[0];
  assertEquals(raw.fetched_at, "2026-11-18T12:00:00.000Z");
  assertEquals(raw.content_sha256.length, 64);
  assertEquals(JSON.stringify(raw.payload).includes("example.test"), false);
  assertEquals(scan.provider_scan_id, valid.provider_scan_id);
  assertEquals(scan.regions.length, 8);
  // Logs carry no ids in the clear and no body numbers.
  const text = JSON.stringify(logs);
  assertEquals(text.includes("user-1"), false);
  assertEquals(text.includes("12400"), false);
});

Deno.test("the same payload hashes the same, whatever the key order", async () => {
  const { deps, calls } = fakeDeps();
  await handle(post(valid), deps);
  const reordered = Object.fromEntries(Object.entries(sections).reverse());
  await handle(post({ ...valid, sections: reordered }), deps);
  assertEquals(calls[0].raw.content_sha256, calls[1].raw.content_sha256);
});

Deno.test("identity fields do not change the hash", async () => {
  const { deps, calls } = fakeDeps();
  await handle(post(valid), deps);
  const renamed = structuredClone(sections);
  renamed["scan-info"].patient_intake.first_name = "Someone else";
  await handle(post({ ...valid, sections: renamed }), deps);
  assertEquals(calls[0].raw.content_sha256, calls[1].raw.content_sha256);
});

Deno.test("a scan failing validation is still stored, as needs_review", async () => {
  const { deps, calls } = fakeDeps();
  const bad = structuredClone(sections);
  bad.composition.total.region_fat_pct = 90;
  const res = await handle(post({ ...valid, sections: bad }), deps);
  assertEquals(res.status, 200);
  assertEquals((await res.json()).scan_status, "needs_review");
  assertEquals(calls[0].scan.status, "needs_review");
});

for (
  const [name, req, status, error] of [
    ["no token", post(valid, ""), 401, "unauthorized"],
    ["bad token", post(valid, "bad"), 401, "unauthorized"],
    [
      "GET",
      new Request("http://localhost", { method: "GET" }),
      405,
      "method_not_allowed",
    ],
    ["not JSON", post("{nope"), 400, "invalid_json"],
    ["JSON array", post("[]"), 400, "invalid_json"],
    [
      "unknown source",
      post({ ...valid, source: "dexafit" }),
      400,
      "unsupported_source",
    ],
    [
      "manual not yet",
      post({ ...valid, source: "manual" }),
      400,
      "unsupported_source",
    ],
    [
      "bad scan id",
      post({ ...valid, provider_scan_id: "../x" }),
      400,
      "invalid_request",
    ],
    [
      "bad fetched_at",
      post({ ...valid, fetched_at: "soon" }),
      400,
      "invalid_request",
    ],
    [
      "sections not an object",
      post({ ...valid, sections: [] }),
      400,
      "invalid_request",
    ],
    [
      "too large",
      post({ ...valid, pad: "x".repeat(MAX_BODY_BYTES) }),
      413,
      "payload_too_large",
    ],
  ] as const
) {
  Deno.test(`rejects ${name}`, async () => {
    const { deps, calls } = fakeDeps();
    const res = await handle(req, deps);
    assertEquals(res.status, status);
    assertEquals((await res.json()).error, error);
    assertEquals(calls.length, 0);
  });
}

Deno.test("refuses users outside the BodySpec beta", async () => {
  let asked: string | undefined;
  const { deps, calls } = fakeDeps({
    featureEnabled: (_u, f) => {
      asked = f;
      return Promise.resolve(false);
    },
  });
  const res = await handle(post(valid), deps);
  assertEquals(res.status, 403);
  assertEquals((await res.json()).error, "not_in_beta");
  assertEquals(asked, "bodyspec_sync");
  assertEquals(calls.length, 0);
});

Deno.test("maps a missing health-data consent to consent_required", async () => {
  const { deps } = fakeDeps({
    ingest: () => Promise.reject(new ConsentRequiredError()),
  });
  const res = await handle(post(valid), deps);
  assertEquals(res.status, 403);
  assertEquals((await res.json()).error, "consent_required");
});

Deno.test("a database failure is a 500 and logs no detail", async () => {
  const { deps, logs } = fakeDeps({
    ingest: () => Promise.reject(new Error("duplicate key: user-1 12400")),
  });
  const res = await handle(post(valid), deps);
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "ingest_failed");
  assert(!JSON.stringify(logs).includes("12400"));
});
