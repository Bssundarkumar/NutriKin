import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const json = (message: string, accepted = false) => new Response(JSON.stringify({ accepted, message }), {
  headers: { "Content-Type": "application/json" },
});
const apnsClient = Deno.createHttpClient({ http1: false, http2: true });
let cachedJWT: { token: string; at: number } | undefined;
async function providerToken(key: string, keyID: string, teamID: string) {
  if (cachedJWT && Date.now() - cachedJWT.at < 45 * 60_000) return cachedJWT.token;
  const token = await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: keyID })
    .setIssuer(teamID).setIssuedAt().sign(await importPKCS8(key.replace(/\\n/g, "\n"), "ES256"));
  cachedJWT = { token, at: Date.now() };
  return token;
}
Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });
  const authorization = req.headers.get("Authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL")!;
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: authorization } } });
  const { data: { user }, error: authError } = await caller.auth.getUser();
  if (authError || !user) return new Response("Unauthorized", { status: 401 });
  const key = Deno.env.get("APNS_PRIVATE_KEY");
  const keyID = Deno.env.get("APNS_KEY_ID");
  const teamID = Deno.env.get("APNS_TEAM_ID");
  const topic = Deno.env.get("APNS_TOPIC");
  if (!key || !keyID || !teamID || !topic) return json("Family reminders are not enabled on the server yet.");
  let pokeID: string | undefined;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  try {
    const { medicationID, dueAt, timezone } = await req.json();
    if (typeof medicationID !== "string" || typeof dueAt !== "string" || typeof timezone !== "string" || timezone.length > 100)
      return json("Invalid reminder.");
    const token = await providerToken(key, keyID, teamID);
    const { data, error } = await caller.rpc("request_medication_poke", { p_medication: medicationID, p_due: dueAt, p_timezone: timezone });
    if (error) return json(error.message);
    const poke = Array.isArray(data) ? data[0] : data;
    pokeID = poke.id;
    const { data: devices, error: deviceError } = await admin.from("push_devices").select("token,environment")
      .eq("user_id", poke.recipient_id).eq("enabled", true);
    if (deviceError) throw deviceError;
    // Check the dose once more immediately before sending.
    const { data: records, error: recordError } = await admin.from("medication_doses").select("id")
      .eq("medication_id", poke.medication_id).eq("due_at", poke.due_at);
    if (recordError) throw recordError;
    if (records?.length) throw new Error("This dose has already been marked taken or skipped.");
    let accepted = 0;
    for (const device of devices ?? []) {
      const host = device.environment === "sandbox" ? "api.sandbox.push.apple.com" : "api.push.apple.com";
      const response = await fetch(`https://${host}/3/device/${device.token}`, {
        client: apnsClient, method: "POST", signal: AbortSignal.timeout(10_000),
        headers: { authorization: `bearer ${token}`, "apns-topic": topic, "apns-push-type": "alert", "apns-priority": "10",
          "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600), "apns-collapse-id": poke.id },
        body: JSON.stringify({ aps: { alert: { title: "Family medication reminder", body: "Someone in your family sent you a reminder. Open NutriKin to check your schedule." }, sound: "default", "thread-id": "family-reminders" }, memberID: poke.member_id, familyReminder: true }),
      }).catch(() => null);
      if (!response) continue;
      if (response.ok) accepted++;
      else {
        const reason = await response.json().catch(() => ({}));
        if (response.status === 410 || reason.reason === "BadDeviceToken")
          await admin.from("push_devices").update({ enabled: false }).eq("token", device.token).eq("user_id", poke.recipient_id);
      }
    }
    await admin.from("medication_pokes").update({ state: accepted ? "accepted" : "failed" }).eq("id", poke.id);
    return accepted ? json("Reminder sent. Delivery depends on their iPhone's notification settings.", true)
      : json("Couldn't deliver the reminder. Ask them to enable Family reminders on their phone.");
  } catch {
    if (pokeID) await admin.from("medication_pokes").update({ state: "failed" }).eq("id", pokeID);
    return json("Couldn't send the reminder. Please try again later.");
  }
});
