// NutriKin: the free, no-setup plate scan path. Every household gets a small number of AI photo estimates
// a day (DAILY_CAP below) on NutriKin's own Gemini key; past that, the app falls back to the on-device
// guesser or asks for the person's own key. This is the ONLY server-side AI feature in NutriKin — chat,
// meal ideas and unlimited plate scans still run on the person's own account or Apple's on-device model,
// exactly as before. See ../gemini-key/README.md sibling doc for the parts of this you must set up yourself.
//
// Deploy: supabase functions deploy plate-scan
// Secrets it needs: supabase secrets set GEMINI_SHARED_KEY=<a Gemini key you hold, on your own Google account>
// Config: DAILY_CAP below (or set DAILY_PLATE_SCAN_CAP as a secret to change it without redeploying code)

const GEMINI_KEY = Deno.env.get("GEMINI_SHARED_KEY") ?? "";
const DAILY_CAP = Number(Deno.env.get("DAILY_PLATE_SCAN_CAP") ?? "3");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}

// The same prompt shape PlateService.swift asks a linked key for, kept in sync by hand — see that file if
// the prompt there changes and this should follow.
const SYSTEM_PROMPT = `
You are a registered-dietitian-level nutrition estimator for a family health app. You estimate what is on ONE
plate from a photo, ideally taken from above. Identify every distinct food, splitting mixed dishes into their
main parts. Include sauces, drinks and cooking fat; skip tiny garnishes; at most 10 items. Estimate cooked
weight in grams as served, and typical nutrition per 100 g as prepared (calories, protein_g, carbs_g, sugar_g,
fiber_g, fat_g, sat_fat_g, sodium_mg), using standard food-composition values. Count the fat and salt cooking
usually adds. Keep calories consistent with the macros. Never invent food that isn't visible; if unsure, name
your best guess, set confidence "low", and list 1-2 alternatives. Only list actual food and drink, never the
plate, board, cutlery, napkin, table or hands. List possible allergens only from: peanuts, nuts, milk, gluten,
eggs, soybeans, fish, crustaceans, sesame. If the plate's size is unknown, estimate its diameter in cm from
cues like cutlery or a glass and report it as plate_diameter_cm.

Reply with JSON only, no other text, in exactly this shape:
{"plate_diameter_cm":26,"items":[{"name":"Basmati rice","grams":180,"per_100g":{"calories":130,"protein_g":2.7,"carbs_g":28,"sugar_g":0.1,"fiber_g":0.4,"fat_g":0.3,"sat_fat_g":0.1,"sodium_mg":250},"confidence":"high","allergens":[],"alternatives":[]}],"note":"one short sentence about the biggest uncertainty"}
If the photo does not show food, reply {"items":[],"note":"No food found in the photo."}
`.trim();

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  if (!GEMINI_KEY) return json({ error: "not_configured", message: "The free daily scans aren't set up yet. Add your own key instead." }, 501);

  const authHeader = req.headers.get("Authorization") ?? "";
  const userToken = authHeader.replace(/^Bearer /, "");
  if (!userToken) return json({ error: "unauthorized" }, 401);

  try {
    const { imageBase64, plateDiameterCm } = await req.json();
    if (!imageBase64) return json({ error: "Missing photo" }, 400);

    // Who is this, and which household are they in? Uses the caller's own token (not the service role) for
    // this lookup, so it's naturally scoped to exactly the rows RLS already lets them see.
    const meRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { Authorization: `Bearer ${userToken}`, apikey: SERVICE_ROLE_KEY },
    });
    const me = await meRes.json();
    if (!meRes.ok || !me.id) return json({ error: "unauthorized" }, 401);

    const membershipRes = await fetch(
      `${SUPABASE_URL}/rest/v1/household_users?user_id=eq.${me.id}&select=household_id&limit=1`,
      { headers: { Authorization: `Bearer ${SERVICE_ROLE_KEY}`, apikey: SERVICE_ROLE_KEY } },
    );
    const memberships = await membershipRes.json();
    const householdId = memberships?.[0]?.household_id;
    if (!householdId) return json({ error: "no_household", message: "Join or create a family first." }, 400);

    // Atomically checks and (if there's room) uses one of today's free scans, all in one database call so
    // two scans started at the same instant can't both slip in under the cap.
    const usageRes = await fetch(`${SUPABASE_URL}/rest/v1/rpc/try_use_plate_scan`, {
      method: "POST",
      headers: { Authorization: `Bearer ${SERVICE_ROLE_KEY}`, apikey: SERVICE_ROLE_KEY, "Content-Type": "application/json" },
      body: JSON.stringify({ hid: householdId, cap: DAILY_CAP }),
    });
    const usage = (await usageRes.json())?.[0];
    if (!usage?.allowed) {
      return json({ error: "limit_reached", message: `You've used today's ${DAILY_CAP} free AI scans. Add your own key for unlimited, or try the basic guess instead.`, remaining: 0 }, 429);
    }

    // Ask Gemini directly, with NutriKin's own key. Only this one photo and this one prompt are sent —
    // nothing else about the family goes to Google through this path.
    const model = "gemini-2.5-flash";
    const geminiRes = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
          contents: [{ parts: [
            { inlineData: { mimeType: "image/jpeg", data: imageBase64 } },
            { text: plateDiameterCm ? `The plate is ${plateDiameterCm} cm across.` : "Estimate the food on this plate." },
          ] }],
          generationConfig: { responseMimeType: "application/json" },
        }),
      },
    );
    const geminiData = await geminiRes.json();
    const text = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text;
    if (!geminiRes.ok || !text) {
      console.error("Gemini error", JSON.stringify(geminiData).slice(0, 500));
      return json({ error: "ai_failed", message: "Couldn't read that photo. Try again, or use the basic guess instead." }, 502);
    }

    // Passed straight through as text: the phone's own PlateParser (the same one used for a linked key)
    // reads and validates this JSON, so the safety clamps live in one place, not duplicated here.
    return json({ resultJSON: text, remaining: Math.max(DAILY_CAP - usage.scans_used, 0) });
  } catch (error) {
    console.error(error);
    return json({ error: "server_error", message: "Something went wrong. Try again, or use the basic guess instead." }, 500);
  }
});
