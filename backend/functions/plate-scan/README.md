# Free daily plate scans (shared key) — setup

This gives every family a few free AI plate-photo estimates a day, on NutriKin's own Gemini key, with zero
setup for them. Past that daily cap, it falls back to the on-device guesser or a linked key. It's off (silent,
no error shown to anyone) until you complete this.

**Status:** built, not deployed. Needs your own Gemini key and a Supabase deploy — both things only you can do.

## 1. Get a Gemini key to hold server-side

This is separate from any key a family member might link themselves. Go to
[aistudio.google.com/apikey](https://aistudio.google.com/apikey), sign in, create a key. This is the one key
that pays for every family's free daily scans, so treat it as something to monitor, not something to share.

## 2. Run the migration

Run `backend/migration_019_shared_plate_scans.sql` in the Supabase SQL Editor, after everything through 018.

## 3. Deploy the function

```bash
supabase secrets set GEMINI_SHARED_KEY=<the key from step 1>
# optional: change the daily cap per household (default is 3 if you skip this)
supabase secrets set DAILY_PLATE_SCAN_CAP=3
supabase functions deploy plate-scan
```

That's it — no app-side config needed. The app calls this function automatically for anyone who hasn't
linked their own key; if the function isn't deployed, it fails silently and nobody sees a difference from
today.

## Choosing the daily cap

There's no fixed "right" number — see the conversation in this project's history for the reasoning, but in
short: start low (3/day is a reasonable default), watch real Gemini usage and cost for a couple of weeks, and
raise or lower `DAILY_PLATE_SCAN_CAP` as a secret update (no redeploy of code needed) once you've seen real
numbers rather than a guess.

## What this does NOT do

- It does not touch chat, meal ideas, or unlimited plate scans for anyone with their own key — those are
  completely unaffected.
- It does not identify who took a photo beyond "which family" for the purpose of the daily count — the photo
  itself goes straight to Gemini and back, nothing is stored on NutriKin's server beyond that day's count.
- It does not guarantee Gemini's own free-tier limits won't be hit first if many families are active at once —
  see the rate-limit discussion in this project's history. If that happens, everyone's free scans quietly stop
  working until Gemini's own quota resets, same graceful fallback either way.

## Privacy policy

`docs/privacy.html` has been updated to say plate photos may pass through NutriKin's own server on this free
path (never on the linked-key or on-device paths). Read it before enabling this in production.
