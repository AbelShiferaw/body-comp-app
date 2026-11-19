// ingest-scan: validates, strips, hashes and normalizes one scan, then writes
// it with ingest_normalized_scan in one transaction (LLD "ingest-scan and the
// sync tables"). The phone posts one scan per request; the BodySpec token
// never reaches us.
//
// The handler is pure over [Deps], so unit tests run it without Supabase.

import { canonicalJson, sha256Hex, stripIdentity } from "./identity.ts";
import { normalizeBodySpec } from "./normalize_bodyspec.ts";

export const MAX_BODY_BYTES = 256 * 1024;

/** Sources this function accepts, and the beta flag each one needs. */
const SOURCES: Record<string, { flag: string }> = {
  bodyspec: { flag: "bodyspec_sync" },
};

export interface IngestOutcome {
  scan_id: string;
  status: "created" | "unchanged" | "updated";
}

export interface Deps {
  /** The user id of a valid access token, or null. */
  userIdFor(jwt: string): Promise<string | null>;
  featureEnabled(userId: string, feature: string): Promise<boolean>;
  /** Throws [ConsentRequiredError] when health_data consent is missing. */
  ingest(userId: string, raw: unknown, scan: unknown): Promise<IngestOutcome>;
  log(event: Record<string, unknown>): void;
  now(): Date;
}

export class ConsentRequiredError extends Error {}

/** Error bodies carry a stable code the app maps to its own copy. */
const fail = (status: number, error: string) =>
  Response.json({ error }, { status });

export async function handle(req: Request, deps: Deps): Promise<Response> {
  const started = performance.now();
  if (req.method !== "POST") return fail(405, "method_not_allowed");

  const jwt = req.headers.get("authorization")?.match(/^Bearer (.+)$/i)?.[1];
  const userId = jwt ? await deps.userIdFor(jwt) : null;
  if (!userId) return fail(401, "unauthorized");
  const userRef = (await sha256Hex(userId)).slice(0, 12);

  const declared = Number(req.headers.get("content-length") ?? "0");
  if (declared > MAX_BODY_BYTES) return fail(413, "payload_too_large");
  const text = await req.text();
  if (new TextEncoder().encode(text).length > MAX_BODY_BYTES) {
    return fail(413, "payload_too_large");
  }

  let body: Record<string, unknown>;
  try {
    const parsed = JSON.parse(text);
    if (
      parsed === null || typeof parsed !== "object" || Array.isArray(parsed)
    ) {
      throw new Error("not an object");
    }
    body = parsed;
  } catch {
    return fail(400, "invalid_json");
  }

  const source = body["source"];
  const providerScanId = body["provider_scan_id"];
  const fetchedAt = body["fetched_at"];
  const sections = body["sections"];
  if (typeof source !== "string" || !(source in SOURCES)) {
    return fail(400, "unsupported_source");
  }
  if (
    typeof providerScanId !== "string" ||
    !/^[A-Za-z0-9_-]{1,200}$/.test(providerScanId) ||
    typeof fetchedAt !== "string" ||
    isNaN(Date.parse(fetchedAt)) ||
    sections === null ||
    typeof sections !== "object" ||
    Array.isArray(sections)
  ) {
    return fail(400, "invalid_request");
  }

  if (!(await deps.featureEnabled(userId, SOURCES[source].flag))) {
    deps.log({ event: "ingest_refused", reason: "not_in_beta", user: userRef });
    return fail(403, "not_in_beta");
  }

  const stripped = stripIdentity(sections) as Record<string, unknown>;
  const contentSha256 = await sha256Hex(canonicalJson(stripped));
  const { scan, reasons } = normalizeBodySpec(
    providerScanId,
    stripped,
    deps.now(),
  );
  const raw = {
    fetched_at: new Date(fetchedAt).toISOString(),
    payload: stripped,
    content_sha256: contentSha256,
  };

  let outcome: IngestOutcome;
  try {
    outcome = await deps.ingest(userId, raw, scan);
  } catch (e) {
    if (e instanceof ConsentRequiredError) {
      deps.log({ event: "ingest_refused", reason: "consent", user: userRef });
      return fail(403, "consent_required");
    }
    deps.log({
      event: "ingest_failed",
      user: userRef,
      error: e instanceof Error ? e.name : "unknown",
    });
    return fail(500, "ingest_failed");
  }

  // Ids, codes and durations only: never tokens or body numbers.
  deps.log({
    event: "ingest_done",
    user: userRef,
    source,
    status: outcome.status,
    scan_status: scan.status,
    review_reasons: reasons,
    normalizer: scan.normalizer_version,
    regions: scan.regions.length,
    ms: Math.round(performance.now() - started),
  });

  return Response.json({
    scan_id: outcome.scan_id,
    status: outcome.status,
    scan_status: scan.status,
  });
}
