// Edge function entry point: wires the handler to Supabase. SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are provided by the edge runtime; the service key
// never leaves the server.

import { createClient } from "@supabase/supabase-js";
import { ConsentRequiredError, type Deps, handle } from "./handler.ts";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false, autoRefreshToken: false } },
);

const deps: Deps = {
  async userIdFor(jwt) {
    const { data, error } = await admin.auth.getUser(jwt);
    return error ? null : data.user?.id ?? null;
  },
  async featureEnabled(userId, feature) {
    const { data, error } = await admin.rpc("feature_enabled_for", {
      p_user_id: userId,
      p_feature: feature,
    });
    if (error) throw new Error(`feature check failed: ${error.code}`);
    return data === true;
  },
  async ingest(userId, raw, scan) {
    const { data, error } = await admin.rpc("ingest_normalized_scan", {
      p_user_id: userId,
      p_raw: raw,
      p_scan: scan,
    });
    if (error?.code === "42501") throw new ConsentRequiredError();
    if (error) throw new Error(`ingest failed: ${error.code}`);
    return data;
  },
  log: (event) => console.log(JSON.stringify(event)),
  now: () => new Date(),
};

Deno.serve((req) => handle(req, deps));
