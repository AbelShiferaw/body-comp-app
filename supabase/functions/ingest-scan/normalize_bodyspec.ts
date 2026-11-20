// BodySpec normalizer, version bodyspec-n1 (LLD "Mapping BodySpec to the
// normalized scan"). Pure: sections in, NormalizedScan out.
//
// Field names read by the BodySpec spike (Nov 14) are relied on directly.
// Fields the spike never printed (weight, A/G ratio, bone density,
// percentiles) are read from the likely keys and left out when absent, so a
// different shape degrades to a missing number, never a failed import.

export const BODYSPEC_NORMALIZER = "bodyspec-n1";

const REGION_KEYS = [
  "left_arm",
  "right_arm",
  "left_leg",
  "right_leg",
  "trunk",
  "android",
  "gynoid",
] as const;

/** Arms, legs and trunk: together with the head they make up the total. */
const LIMB_AND_TRUNK = [
  "left_arm",
  "right_arm",
  "left_leg",
  "right_leg",
  "trunk",
] as const;

export interface NormalizedRegion {
  region: string;
  lean_g: number;
  fat_g: number;
  bone_g?: number;
  fat_pct?: number;
  derived?: boolean;
}

export interface NormalizedScan {
  source: string;
  provider_scan_id: string;
  scanned_at: string;
  normalizer_version: string;
  status: "ok" | "needs_review";
  height_cm?: number;
  weight_g?: number;
  fat_g?: number;
  lean_g?: number;
  bone_g?: number;
  body_fat_pct?: number;
  vat_g?: number;
  android_gynoid_ratio?: number;
  rmr?: unknown;
  regions: NormalizedRegion[];
  bone_density: {
    site: string;
    bmd_g_cm2?: number;
    t_score?: number;
    z_score?: number;
  }[];
  percentiles: {
    metric: string;
    percentile?: number;
    band?: string;
    reference_group?: string;
  }[];
}

/** Why a scan needs review. Stable codes, safe to log. */
export type ReviewReason =
  | "missing_scan_time"
  | "missing_totals"
  | "missing_region"
  | "negative_mass"
  | "regions_do_not_sum"
  | "body_fat_out_of_range"
  | "height_out_of_range"
  | "scanned_in_future";

export interface NormalizeResult {
  scan: NormalizedScan;
  reasons: ReviewReason[];
}

type Json = Record<string, unknown>;

const obj = (v: unknown): Json | undefined =>
  v !== null && typeof v === "object" && !Array.isArray(v)
    ? (v as Json)
    : undefined;

const num = (v: unknown): number | undefined =>
  typeof v === "number" && Number.isFinite(v) ? v : undefined;

/** The first key of [o] that holds a finite number. */
const firstNum = (o: Json | undefined, ...keys: string[]) => {
  for (const k of keys) {
    const n = num(o?.[k]);
    if (n !== undefined) return n;
  }
  return undefined;
};

const grams = (kg: number | undefined) =>
  kg === undefined ? undefined : Math.round(kg * 1000);

const round1 = (x: number) => Math.round(x * 10) / 10;

/**
 * Maps one BodySpec result (its detail plus six DEXA sections) to the
 * normalized scan. [now] is injected so tests can pin "not in the future".
 */
export function normalizeBodySpec(
  providerScanId: string,
  sections: Json,
  now: Date = new Date(),
): NormalizeResult {
  const reasons: ReviewReason[] = [];
  const detail = obj(sections["detail"]);
  const scanInfo = obj(sections["scan-info"]);
  const composition = obj(sections["composition"]);
  const visceral = obj(sections["visceral-fat"]);
  const intake = obj(scanInfo?.["patient_intake"]);
  const total = obj(composition?.["total"]);
  const regionsIn = obj(composition?.["regions"]);

  const startTime = typeof detail?.["start_time"] === "string"
    ? new Date(detail["start_time"] as string)
    : undefined;
  const scannedAt = startTime && !isNaN(startTime.getTime())
    ? startTime
    : undefined;
  if (!scannedAt) reasons.push("missing_scan_time");
  else if (scannedAt.getTime() > now.getTime() + 5 * 60_000) {
    reasons.push("scanned_in_future");
  }

  const fatKg = firstNum(total, "fat_mass_kg");
  const leanKg = firstNum(total, "lean_mass_kg");
  const boneKg = firstNum(total, "bone_mass_kg");
  if (fatKg === undefined || leanKg === undefined) {
    reasons.push("missing_totals");
  }
  const bodyFatPct = firstNum(total, "region_fat_pct");
  if (bodyFatPct !== undefined && (bodyFatPct < 2 || bodyFatPct > 70)) {
    reasons.push("body_fat_out_of_range");
  }

  const heightCm = firstNum(intake, "height_cm");
  if (heightCm !== undefined && (heightCm < 120 || heightCm > 230)) {
    reasons.push("height_out_of_range");
  }

  // Weight at scan: the intake weight when BodySpec reports one, else the
  // DEXA total mass (fat + lean + bone), which is what the scanner weighed.
  const weightKg = firstNum(intake, "weight_kg") ??
    firstNum(total, "total_mass_kg") ??
    (fatKg !== undefined && leanKg !== undefined && boneKg !== undefined
      ? fatKg + leanKg + boneKg
      : undefined);

  const regions: NormalizedRegion[] = [];
  for (const key of REGION_KEYS) {
    const r = obj(regionsIn?.[key]);
    const lean = firstNum(r, "lean_mass_kg");
    const fat = firstNum(r, "fat_mass_kg");
    if (lean === undefined || fat === undefined) {
      reasons.push("missing_region");
      continue;
    }
    if (lean < 0 || fat < 0) reasons.push("negative_mass");
    const bone = firstNum(r, "bone_mass_kg");
    const pct = firstNum(r, "region_fat_pct");
    regions.push({
      region: key,
      lean_g: Math.max(0, grams(lean)!),
      fat_g: Math.max(0, grams(fat)!),
      ...(bone !== undefined && bone >= 0 ? { bone_g: grams(bone) } : {}),
      ...(pct !== undefined ? { fat_pct: round1(pct) } : {}),
    });
  }

  // BodySpec reports no head region: head = total minus arms, legs, trunk.
  // The head must come out non-negative and plausible: the parts may exceed
  // the total by at most 2% (rounding), and the head may not take more than
  // a quarter of the total (a sign that a region went missing or changed).
  const parts = regions.filter((r) =>
    (LIMB_AND_TRUNK as readonly string[]).includes(r.region)
  );
  if (
    parts.length === LIMB_AND_TRUNK.length &&
    fatKg !== undefined &&
    leanKg !== undefined
  ) {
    const totalLeanG = grams(leanKg)!;
    const totalFatG = grams(fatKg)!;
    const partsLean = parts.reduce((s, r) => s + r.lean_g, 0);
    const partsFat = parts.reduce((s, r) => s + r.fat_g, 0);
    const headLean = totalLeanG - partsLean;
    const headFat = totalFatG - partsFat;
    const offBy = (parts: number, total: number) =>
      parts > total * 1.02 || parts < total * 0.75;
    if (
      headLean < 0 || headFat < 0 ||
      offBy(partsLean, totalLeanG) || offBy(partsFat, totalFatG)
    ) {
      reasons.push("regions_do_not_sum");
    } else {
      regions.push({
        region: "head",
        lean_g: headLean,
        fat_g: headFat,
        derived: true,
      });
    }
  }

  const scan: NormalizedScan = {
    source: "bodyspec",
    provider_scan_id: providerScanId,
    scanned_at: (scannedAt ?? now).toISOString(),
    normalizer_version: BODYSPEC_NORMALIZER,
    status: reasons.length === 0 ? "ok" : "needs_review",
    height_cm: heightCm === undefined ? undefined : round1(heightCm),
    weight_g: grams(weightKg),
    fat_g: grams(fatKg),
    lean_g: grams(leanKg),
    bone_g: grams(boneKg),
    body_fat_pct: bodyFatPct === undefined ? undefined : round1(bodyFatPct),
    vat_g: grams(firstNum(visceral, "vat_mass_kg")),
    android_gynoid_ratio: androidGynoidRatio(composition),
    rmr: obj(sections["rmr"]) ?? undefined,
    regions,
    bone_density: boneDensity(sections["bone-density"]),
    percentiles: percentiles(sections["percentiles"]),
  };
  return { scan: dropUndefined(scan), reasons: [...new Set(reasons)] };
}

function androidGynoidRatio(composition: Json | undefined) {
  const direct = firstNum(
    composition,
    "android_gynoid_ratio",
    "ag_ratio",
    "a_g_ratio",
  );
  if (direct !== undefined) return Math.round(direct * 100) / 100;
  const regions = obj(composition?.["regions"]);
  const a = firstNum(obj(regions?.["android"]), "region_fat_pct");
  const g = firstNum(obj(regions?.["gynoid"]), "region_fat_pct");
  return a !== undefined && g !== undefined && g > 0
    ? Math.round((a / g) * 100) / 100
    : undefined;
}

/** Bone density per site, from either `{regions: {site: {...}}}` or a list. */
function boneDensity(section: unknown): NormalizedScan["bone_density"] {
  const s = obj(section);
  const entries: [string, Json][] = [];
  const fromMap = obj(s?.["regions"]) ?? obj(s?.["sites"]);
  if (fromMap) {
    for (const [site, v] of Object.entries(fromMap)) {
      const o = obj(v);
      if (o) entries.push([site, o]);
    }
  }
  const list = Array.isArray(section)
    ? section
    : Array.isArray(s?.["regions"])
    ? s!["regions"] as unknown[]
    : [];
  for (const v of list) {
    const o = obj(v);
    const site = o?.["site"] ?? o?.["region"];
    if (o && typeof site === "string") entries.push([site, o]);
  }
  const total = obj(s?.["total"]);
  if (total) entries.push(["total", total]);

  return entries
    .filter(([site]) => site.length >= 1 && site.length <= 40)
    .map(([site, o]) =>
      dropUndefined({
        site,
        bmd_g_cm2: firstNum(o, "bmd_g_cm2", "bmd"),
        t_score: firstNum(o, "t_score"),
        z_score: firstNum(o, "z_score"),
      })
    );
}

const BANDS = new Set(["green", "yellow", "red"]);

/** Percentiles per metric, from either a map of metrics or a list. */
function percentiles(section: unknown): NormalizedScan["percentiles"] {
  const s = obj(section);
  const entries: [string, Json][] = [];
  const list = Array.isArray(section)
    ? section
    : Array.isArray(s?.["percentiles"])
    ? s!["percentiles"] as unknown[]
    : undefined;
  if (list) {
    for (const v of list) {
      const o = obj(v);
      const metric = o?.["metric"];
      if (o && typeof metric === "string") entries.push([metric, o]);
    }
  } else if (s) {
    for (const [metric, v] of Object.entries(s)) {
      const o = obj(v);
      if (o && num(o["percentile"]) !== undefined) entries.push([metric, o]);
    }
  }
  const referenceGroup = typeof s?.["reference_group"] === "string"
    ? (s["reference_group"] as string).slice(0, 80)
    : undefined;

  return entries
    .filter(([metric]) => metric.length >= 1 && metric.length <= 60)
    .map(([metric, o]) => {
      const p = firstNum(o, "percentile");
      const band = typeof o["band"] === "string"
        ? (o["band"] as string).toLowerCase()
        : undefined;
      return dropUndefined({
        metric,
        percentile: p !== undefined && p >= 0 && p <= 100
          ? round1(p)
          : undefined,
        band: band && BANDS.has(band) ? band : undefined,
        reference_group: referenceGroup,
      });
    });
}

function dropUndefined<T extends object>(o: T): T {
  return Object.fromEntries(
    Object.entries(o).filter(([, v]) => v !== undefined),
  ) as T;
}
