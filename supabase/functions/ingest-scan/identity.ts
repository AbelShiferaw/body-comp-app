// Identity stripping and content hashing for raw provider payloads.
//
// Every source's raw sections lose identity fields before they are stored
// (Abel's sync LLD review, Nov 19): we keep the composition data unchanged
// but never keep identity we do not use, so the privacy policy stays true.

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
]);

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
