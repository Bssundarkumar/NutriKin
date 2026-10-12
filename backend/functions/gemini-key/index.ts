// NutriKin: creates a Gemini API key inside the SIGNED-IN PERSON'S OWN Google Cloud project, from the
// one-time authorization code their phone got after they signed in with Google. Their password never
// reaches this function or NutriKin; only a short-lived authorization code does, exactly once.
//
// BETA. Needs one-time setup — see ../../docs/google-oauth-setup.md — before this can be deployed and
// before GoogleOAuthConfig.clientID is filled in on the app side. Until then, the app hides this feature.
//
// Deploy: supabase functions deploy gemini-key
// Secrets it needs (supabase secrets set ...): GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET
//
// NOTE: creating a Google Cloud project, enabling an API on it, and creating a restricted key are each
// asynchronous Google Cloud operations. This function polls each step with a short timeout and gives up
// with a clear error rather than hanging — the person can always add a key manually instead.

const GOOGLE_CLIENT_ID = Deno.env.get("GOOGLE_CLIENT_ID") ?? "";
const GOOGLE_CLIENT_SECRET = Deno.env.get("GOOGLE_CLIENT_SECRET") ?? "";
const GENERATIVE_LANGUAGE_SERVICE = "generativelanguage.googleapis.com";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

async function googleFetch(url: string, accessToken: string, init: RequestInit = {}) {
  const res = await fetch(url, {
    ...init,
    headers: { ...(init.headers ?? {}), Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${url} failed: ${res.status} ${JSON.stringify(data).slice(0, 300)}`);
  return data;
}

/// Google's long-running operations (create project, enable API, create key) all follow the same shape:
/// poll GET on the operation's name until `done` is true, then read `response`.
async function waitForOperation(name: string, accessToken: string, host: string, timeoutMs = 45_000) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const op = await googleFetch(`https://${host}/v1/${name}`, accessToken);
    if (op.done) {
      if (op.error) throw new Error(`Google operation failed: ${JSON.stringify(op.error)}`);
      return op.response;
    }
    await new Promise((r) => setTimeout(r, 1500));
  }
  throw new Error("Timed out waiting for Google to finish setting up the project.");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!GOOGLE_CLIENT_ID || !GOOGLE_CLIENT_SECRET) {
    return json({ error: "This server isn't set up for automatic Google sign-in yet. Add a key manually instead." }, 501);
  }

  try {
    const { code, codeVerifier, redirectUri } = await req.json();
    if (!code || !codeVerifier || !redirectUri) return json({ error: "Missing code" }, 400);

    // 1) Exchange the one-time authorization code for tokens. PKCE (codeVerifier) proves this request came
    //    from the same app instance that started the sign-in, so a copied/leaked code alone isn't enough.
    const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        code, client_id: GOOGLE_CLIENT_ID, client_secret: GOOGLE_CLIENT_SECRET,
        redirect_uri: redirectUri, grant_type: "authorization_code", code_verifier: codeVerifier,
      }),
    });
    const tokens = await tokenRes.json();
    if (!tokenRes.ok || !tokens.access_token) {
      return json({ error: "Google sign-in didn't complete. Please try again." }, 400);
    }
    const accessToken: string = tokens.access_token;

    // 2) Create a fresh Google Cloud project for this person to hold the key. A random suffix keeps the
    //    project ID unique across everyone who's ever used this flow (Google project IDs are globally unique).
    const projectId = `nutrikin-${crypto.randomUUID().slice(0, 8)}`;
    const createProjectOp = await googleFetch(
      "https://cloudresourcemanager.googleapis.com/v3/projects", accessToken,
      { method: "POST", body: JSON.stringify({ projectId, displayName: "NutriKin (Gemini)" }) },
    );
    const project = await waitForOperation(createProjectOp.name, accessToken, "cloudresourcemanager.googleapis.com");
    const projectNumber: string = project.name.split("/")[1]; // "projects/123456" -> "123456"

    // 3) Turn on the Gemini API for that project. A brand-new project has no APIs enabled by default.
    const enableOp = await googleFetch(
      `https://serviceusage.googleapis.com/v1/projects/${projectNumber}/services/${GENERATIVE_LANGUAGE_SERVICE}:enable`,
      accessToken, { method: "POST" },
    );
    if (!enableOp.done) await waitForOperation(enableOp.name, accessToken, "serviceusage.googleapis.com");

    // 4) Create an API key restricted to ONLY the Gemini API — not a general-purpose Cloud key — so if it
    //    were ever misused, the blast radius is just Gemini calls on this one project, nothing else.
    const createKeyOp = await googleFetch(
      `https://apikeys.googleapis.com/v2/projects/${projectNumber}/locations/global/keys`, accessToken,
      {
        method: "POST",
        body: JSON.stringify({
          displayName: "NutriKin",
          restrictions: { apiTargets: [{ service: GENERATIVE_LANGUAGE_SERVICE }] },
        }),
      },
    );
    const keyResource = await waitForOperation(createKeyOp.name, accessToken, "apikeys.googleapis.com");

    // 5) The create response doesn't include the actual key string — that needs a separate read.
    const keyString = await googleFetch(`https://apikeys.googleapis.com/v2/${keyResource.name}/keyString`, accessToken);

    return json({ apiKey: keyString.keyString });
  } catch (error) {
    console.error(error);
    return json({ error: "Couldn't finish setting up Google automatically. Please add a key manually instead." }, 500);
  }
});
