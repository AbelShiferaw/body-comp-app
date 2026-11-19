// deno-lint-ignore-file no-explicit-any -- fixtures are untyped JSON
import { assert, assertEquals } from "@std/assert";
import { stripIdentity } from "./identity.ts";
import {
  BODYSPEC_NORMALIZER,
  normalizeBodySpec,
} from "./normalize_bodyspec.ts";

const fixture = () =>
  structuredClone(
    JSON.parse(
      Deno.readTextFileSync(
        new URL("./fixtures/bodyspec_result.json", import.meta.url),
      ),
    ),
  );
const now = new Date("2026-11-19T00:00:00Z");
const normalize = (sections: Record<string, unknown>) =>
  normalizeBodySpec("result-1", sections, now);

Deno.test("maps a full result to grams, with a derived head", () => {
  const { scan, reasons } = normalize(fixture());
  assertEquals(reasons, []);
  assertEquals(scan.status, "ok");
  assertEquals(scan.normalizer_version, BODYSPEC_NORMALIZER);
  assertEquals(scan.scanned_at, "2026-10-04T16:20:00.000Z");
  assertEquals(scan.height_cm, 180.3);
  assertEquals(scan.weight_g, 81200);
  assertEquals(scan.fat_g, 12400);
  assertEquals(scan.lean_g, 64900);
  assertEquals(scan.bone_g, 3520);
  assertEquals(scan.body_fat_pct, 15.4);
  assertEquals(scan.vat_g, 310);
  assertEquals(scan.regions.length, 8);
  assertEquals(scan.regions[0], {
    region: "left_arm",
    lean_g: 4120,
    fat_g: 710,
    bone_g: 210,
    fat_pct: 14.7,
  });
  const head = scan.regions.find((r) => r.region === "head")!;
  // 64.9 - (4.12 + 4.31 + 11.02 + 11.24 + 30.11) = 4.10 kg lean
  assertEquals(head, {
    region: "head",
    lean_g: 4100,
    fat_g: 870,
    derived: true,
  });
  assert(!scan.regions.find((r) => r.region === "android")!.bone_g);
});

Deno.test("reads bone density, percentiles, rmr and the A/G ratio", () => {
  const { scan } = normalize(fixture());
  assertEquals(scan.bone_density, [
    { site: "spine", bmd_g_cm2: 1.21, t_score: 0.9, z_score: 0.8 },
    { site: "total", bmd_g_cm2: 1.312, t_score: 1.4, z_score: 1.2 },
  ]);
  assertEquals(scan.percentiles, [
    {
      metric: "body_fat_pct",
      percentile: 82,
      band: "green",
      reference_group: "male 30-39",
    },
    {
      metric: "lean_mass_index",
      percentile: 74,
      band: "green",
      reference_group: "male 30-39",
    },
  ]);
  assertEquals((scan.rmr as Record<string, number>).cunningham, 1928);
  // No direct ratio in the fixture: android fat % / gynoid fat %.
  assertEquals(scan.android_gynoid_ratio, 1.03);
});

Deno.test("a missing optional section imports without it", () => {
  const s = fixture();
  delete s["bone-density"];
  delete s["percentiles"];
  delete s["rmr"];
  delete s["scan-info"].patient_intake.weight_kg;
  const { scan, reasons } = normalize(s);
  assertEquals(reasons, []);
  assertEquals(scan.bone_density, []);
  assertEquals(scan.percentiles, []);
  assertEquals(scan.rmr, undefined);
  // Falls back to the DEXA total mass.
  assertEquals(scan.weight_g, 80820);
});

Deno.test("rounds kg to whole grams", () => {
  const s = fixture();
  s.composition.total.fat_mass_kg = 12.40049;
  assertEquals(normalize(s).scan.fat_g, 12400);
});

for (
  const [name, change, reason] of [
    [
      "missing region",
      (s: any) => delete s.composition.regions.trunk,
      "missing_region",
    ],
    [
      "negative mass",
      (s: any) => (s.composition.regions.left_arm.fat_mass_kg = -1),
      "negative_mass",
    ],
    [
      "negative head",
      (s: any) => (s.composition.total.lean_mass_kg = 50),
      "regions_do_not_sum",
    ],
    [
      "head too large",
      (s: any) => (s.composition.total.lean_mass_kg = 90),
      "regions_do_not_sum",
    ],
    [
      "body fat too low",
      (s: any) => (s.composition.total.region_fat_pct = 1.5),
      "body_fat_out_of_range",
    ],
    [
      "body fat too high",
      (s: any) => (s.composition.total.region_fat_pct = 71),
      "body_fat_out_of_range",
    ],
    [
      "height too low",
      (s: any) => (s["scan-info"].patient_intake.height_cm = 110),
      "height_out_of_range",
    ],
    [
      "height too high",
      (s: any) => (s["scan-info"].patient_intake.height_cm = 231),
      "height_out_of_range",
    ],
    [
      "future scan",
      (s: any) => (s.detail.start_time = "2026-12-01T00:00:00Z"),
      "scanned_in_future",
    ],
    [
      "no scan time",
      (s: any) => delete s.detail.start_time,
      "missing_scan_time",
    ],
    ["no totals", (s: any) => delete s.composition.total, "missing_totals"],
  ] as const
) {
  Deno.test(`needs review: ${name}`, () => {
    const s = fixture();
    change(s);
    const { scan, reasons } = normalize(s);
    assertEquals(scan.status, "needs_review");
    assert(reasons.includes(reason), `${reasons} has ${reason}`);
    // Nothing the database would reject: every region row is complete.
    for (const r of scan.regions) assert(r.lean_g >= 0 && r.fat_g >= 0);
  });
}

Deno.test("normalizes the stripped payload the same way", () => {
  const stripped = stripIdentity(fixture()) as Record<string, unknown>;
  assertEquals(normalize(stripped).reasons, []);
});
