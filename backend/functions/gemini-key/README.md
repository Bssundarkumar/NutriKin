# Automatic Gemini key sign-in (beta) — setup

This lets someone tap "Sign in with Google" and get a working Gemini key automatically, instead of visiting
Google AI Studio themselves. It's off by default and invisible in the app until you complete this.

**Status:** built, but untested end to end — it needs real Google Cloud credentials, which only you can create
(they're tied to your identity as the developer). Test it yourself before relying on it, and expect to debug
the Google Cloud API calls in `index.ts` against real responses; some detail (an exact field name, a required
extra permission) may need adjusting once you can see real errors.

## 1. Create a Google Cloud project for NutriKin itself

This is separate from any project the flow creates for end users — it's the "app" that's allowed to ask
people for permission.

1. Go to [console.cloud.google.com](https://console.cloud.google.com), sign in, create a new project (e.g. "NutriKin").
2. In that project, go to **APIs & Services → OAuth consent screen**.
3. Choose **External** (so any Google account can eventually use it, not just yours).
4. Fill in the app name (NutriKin), your support email, and your contact email.
5. Under **Scopes**, add `https://www.googleapis.com/auth/cloud-platform`. Google will mark this "sensitive" —
   that's expected, and it's why verification (step 5 below) is required before this can go fully public.
6. Under **Test users**, add your own Google account and anyone else (up to 100) who should be able to use this
   before Google finishes reviewing it.

## 2. Create the OAuth client ID

1. Still in APIs & Services, go to **Credentials → Create Credentials → OAuth client ID**.
2. Application type: **iOS**.
3. Bundle ID: `com.sundarBandiguptapu.NutriKin`.
4. Save it. Copy the **Client ID** it gives you.
5. Also go to **Credentials** and note the **Client secret** for the same client (iOS clients still get one for
   this flow, since the actual token exchange happens on the server, not the phone).

## 3. Enable the APIs this flow calls

In your NutriKin Cloud project, **APIs & Services → Library**, enable:
- Cloud Resource Manager API
- Service Usage API
- API Keys API

## 4. Fill in the app and server config

- **App side:** open `FamilyFoodScanner/Services/AI/GoogleKeyProvisioning.swift` and set
  `GoogleOAuthConfig.clientID` to the Client ID from step 2. The feature turns itself on in Connect AI as soon
  as this is non-empty.
- **Server side:**
  ```bash
  supabase secrets set GOOGLE_CLIENT_ID=<client id>
  supabase secrets set GOOGLE_CLIENT_SECRET=<client secret>
  supabase functions deploy gemini-key
  ```

## 5. Submit for Google's verification, when you're ready to go beyond test users

Google requires a review before a `cloud-platform`-scoped app can be used by the public, not just your 100
test accounts. In the OAuth consent screen page, click **Publish App**, then **Submit for verification**.
Expect this to take real time (days to weeks) and possibly a request for a demo video showing exactly what the
app does with the permission. Until it's approved, only your named test users can complete this flow — everyone
else should keep using the manual "paste your key" option, which always works regardless of this.

## What this does NOT do

- It does not touch or see the person's Google password — that's handled entirely by Google's own sign-in page.
- It does not create a shared or pooled key — each person gets their own key, in their own new Google Cloud
  project, under their own Google account and quota.
- It does not guarantee the free tier — a freshly created project's tier depends on that Google account's own
  history with Google Cloud, which this flow has no control over.
