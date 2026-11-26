// Identity stripping and content hashing for raw provider payloads.
//
// Every source's raw sections lose identity fields before they are stored
// (Abel's sync LLD review, Nov 19): we keep the composition data unchanged
// but never keep identity we do not use, so the privacy policy stays true.
//
// Two layers, so a key we did not foresee is never stored: an allow-list of
// the sections (and, in the sections that describe the person, the keys)
// a source's normalizer reads, then a deny-list of identity keys removed at
// any depth inside what is left.

/**
 * What is kept of each source's raw sections. `true` keeps the whole section
 * (composition data); an object keeps only the keys it names, recursively.
 * Sections not named are dropped. A new section is stored once it is added
 * here, after checking a real payload for identity fields.
 */
type Keep = true | { [key: string]: Keep };
const ALLOWED_SECTIONS: Record<string, { [section: string]: Keep }> = {
  bodyspec: {
    detail: { result_id: true, start_time: true, sections: true },
    "scan-info": { patient_intake: { height_cm: true, weight_kg: true } },
    composition: true,
    "visceral-fat": true,
    "bone-density": true,
    percentiles: true,
    rmr: true,
  },
};

/** Keys removed wherever they appear, compared case-insensitively. */
const IDENTITY_KEYS = new Set([
  "name",
  "first_name",
  "middle_name",
  "last_name",
  "full_name",
  "given_name",
  "family_name",
  "preferred_name",
  "patient_name",
  "email",
  "email_address",
  "phone",
  "phone_number",
  "mobile",
  "mobile_phone",
  "birth_date",
  "birthdate",
  "date_of_birth",
  "dob",
  "birthday",
  "address",
  "address_line1",
  "address_line2",
  "street",
  "street_address",
  "city",
  "zip",
  "zip_code",
  "postal_code",
  "address_1",
  "address_2",
  "state",
  "country",
  "phone_mobile",
  "username",
  "user_id",
  "patient",
  "patient_id",
  "mrn",
  "ssn",
  "age",
  "gender",
  "ethnicity",
  "race",
  "location",
  "clinic",
  "operator",
  "technician",
  "notes",
]);

/**
 * The parts of [sections] that [source] is allowed to store, with identity
 * keys removed at any depth. Sources with no allow-list keep nothing.
 */
export function keepForStorage(
  source: string,
  sections: Record<string, unknown>,
): Record<string, unknown> {
  const allowed = Object.hasOwn(ALLOWED_SECTIONS, source)
    ? ALLOWED_SECTIONS[source]
    : {};
  return stripIdentity(pick(sections, allowed)) as Record<string, unknown>;
}

function pick(value: unknown, keep: Keep): unknown {
  if (keep === true) return value;
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    return undefined;
  }
  const out: Record<string, unknown> = {};
  for (const [k, sub] of Object.entries(keep)) {
    if (!Object.hasOwn(value, k)) continue;
    const v = pick((value as Record<string, unknown>)[k], sub);
    if (v !== undefined) out[k] = v;
  }
  return out;
}

/** A copy of [value] with every identity key removed, at any depth. */
export function stripIdentity(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stripIdentity);
  if (value !== null && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value)) {
      if (IDENTITY_KEYS.has(k.toLowerCase())) continue;
      out[k] = stripIdentity(v);
    }
    return out;
  }
  return value;
}

/** JSON with object keys sorted, so equal content always hashes the same. */
export function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value)
      .filter(([, v]) => v !== undefined)
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
      .map(([k, v]) => `${JSON.stringify(k)}:${canonicalJson(v)}`);
    return `{${entries.join(",")}}`;
  }
  return JSON.stringify(value) ?? "null";
}

export async function sha256Hex(text: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(text),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
