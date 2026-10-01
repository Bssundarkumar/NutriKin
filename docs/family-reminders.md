# Family medication reminders

The Family page includes an opt-in **Receive family reminders** switch. A family member can select **Remind them** on an outstanding dose for someone with their own linked account. This sends a remote notification to that person's registered iPhones, including while NutriKin is closed. A reminder does not mark the dose taken.

## Deployment required

1. Apply `backend/migration_021_family_reminders.sql` after migration 020.
2. Enable Push Notifications on the NutriKin App ID and regenerate signing profiles. The project includes the APNs entitlement; release signing uses the production environment.
3. Create an Apple APNs signing key. Set server-only secrets `APNS_PRIVATE_KEY` (the `.p8` contents), `APNS_KEY_ID`, `APNS_TEAM_ID` and `APNS_TOPIC` (`com.sundarBandiguptapu.NutriKin`) in Supabase. Never put the private key or service-role key in the app.
4. Deploy `backend/functions/medication-poke` with normal JWT verification enabled.
5. On the receiving iPhone, link its member profile to its signed-in account and enable Family reminders. Allow iOS notifications.

The `medication-poke` function was deployed from the terminal to the Nutrikin Supabase project (`guihtuotohipipagkbri`) on October 1, 2026. Its verified status is ACTIVE, version 1, with JWT verification enabled. All four APNs secret names are present on the server; their values were not retrieved or validated. The database migration was not applied or verified during this deployment, and no real push was sent. Simulator UI previews cannot establish end-to-end delivery.

## Behaviour and checks

- The function validates the user's session; the SQL function verifies current household membership, the recipient's linked account, the scheduled dose's local time/weekday, and an outstanding dose from the last 24 hours.
- A recipient row lock serializes requests; reminders to the same recipient are limited to one per 15 minutes across all family senders. Taken/skipped doses cannot be nudged. A second check runs immediately before APNs delivery.
- Device tokens are readable only by their owner. Registration rebinds a token to the signed-in account. Sign-out disables registration before removing the session. APNs-invalid tokens are disabled.
- Notification text hides names and medicine details. Tapping opens Today for the corresponding family member; the app validates membership before selecting them.
- The UI reports success only after at least one APNs acceptance. Acceptance is not a delivery receipt: Focus, notification settings, connectivity and iOS determine display. No server credentials, no registered device, cooldown and delivery failures produce an explicit message.
- A short unavoidable race remains if the dose is marked taken after the last check but before the notification displays. No dose is changed by sending or opening a reminder.

Before shipping, test with two real signed-in iPhones: opt-in/out, foreground/background/terminated delivery, notification tap, taken/skipped rejection, wrong-family rejection, simultaneous cooldown attempts, account switching and invalid device tokens.

Implementation follows [Apple's APNs request documentation](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns), [token-based authentication](https://developer.apple.com/documentation/UserNotifications/establishing-a-token-based-connection-to-apns), and [Supabase authenticated Edge Functions](https://supabase.com/docs/guides/functions/auth-legacy-jwt).
