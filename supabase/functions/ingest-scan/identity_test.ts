// deno-lint-ignore-file no-explicit-any -- fixtures are untyped JSON
import { assertEquals, assertNotEquals } from "@std/assert";
import { canonicalJson, sha256Hex, stripIdentity } from "./identity.ts";

const fixture = () =>
  JSON.parse(
    Deno.readTextFileSync(
      new URL("./fixtures/bodyspec_result.json", import.meta.url),
    ),
  );

Deno.test("strips identity fields at any depth and keeps body data", () => {
  const out = stripIdentity(fixture()) as any;
  const text = JSON.stringify(out);
  for (
    const v of [
      "Test",
      "Person",
      "example.test",
      "1990-01-01",
      "555",
      "Testville",
      "Example Clinic",
    ]
  ) {
    assertEquals(text.includes(v), false, `${v} was not stripped`);
  }
  assertEquals(out["scan-info"].patient_intake, {
    height_cm: 180.3,
    weight_kg: 81.2,
  });
  assertEquals(out.composition.total.fat_mass_kg, 12.4);
  assertEquals(out.detail.result_id, "0f3c9a7e5b2d4c8a9e1f6b3d7a2c5e90");
});

Deno.test("matches identity keys case-insensitively, inside arrays too", () => {
  assertEquals(
    stripIdentity({ list: [{ Email: "a@b.c", value: 1 }], DOB: "x" }),
    { list: [{ value: 1 }] },
  );
});

Deno.test("canonical JSON ignores key order", async () => {
  const a = await sha256Hex(canonicalJson({ b: 1, a: { d: [1, 2], c: null } }));
  const b = await sha256Hex(canonicalJson({ a: { c: null, d: [1, 2] }, b: 1 }));
  assertEquals(a, b);
  assertEquals(a.length, 64);
  assertNotEquals(
    a,
    await sha256Hex(canonicalJson({ b: 2, a: { d: [1, 2], c: null } })),
  );
});
