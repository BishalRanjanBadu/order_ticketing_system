# Setting Up Push Notifications

This is the one part I genuinely can't do for you — deploying to your
Supabase project requires *your* login, not mine. Everything else (the
schema, the client code, the service worker) is already built and will
work the moment you finish these steps. It's four steps, roughly 15 minutes.

## What you're setting up

```
Order event happens
       │
       ▼
Postgres trigger writes a row to `notifications`   ← already done, no action needed
       │
       ▼
Database Webhook fires automatically                ← you configure this (step 3)
       │
       ▼
Edge Function `send-push` runs                       ← you deploy this (step 2)
       │
       ▼
Web Push service (Google/Apple/Mozilla) delivers it
       │
       ▼
Your phone/laptop shows the notification              ← the service worker (already built)
```

## Step 1 — Install the Supabase CLI

```bash
npm install -g supabase
```

Then log in and link this project (run from the folder containing `schema.sql`):

```bash
supabase login
supabase link --project-ref <your-project-ref>
```

Your project ref is the subdomain in your Project URL — e.g. if your URL is
`https://mhagyxhqslwggcfhppau.supabase.co`, the ref is `mhagyxhqslwggcfhppau`.

## Step 2 — Set secrets and deploy the Edge Function

The function needs your VAPID keypair (already generated for you below) and
a contact identifier the push services require.

```bash
supabase secrets set VAPID_PUBLIC_KEY="BDBt8LpKQIqIM9GEXTo0oGGDGMDwW2L-bx8jzPBQs0-Ci7CBh_YeDF1kdFAbFPoAy-QjVWhoJMMQu1vIjwTOAlk"
supabase secrets set VAPID_PRIVATE_KEY="Nbud5NjhEFhQRENZCWhemRe260jqMamJLU4yytmfLQI"
supabase secrets set VAPID_SUBJECT="mailto:you@example.com"
```

**Replace `you@example.com` with a real contact email** — it's not shown to
users, but push services use it to reach you if something's wrong with your
setup. `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` don't need to be set —
Supabase gives every Edge Function those two automatically.

⚠️ **The private key above is only as secret as this document.** It's fine
to use as-is to get started, but since it's now been shared in this chat,
treat it as semi-public: don't publish this file anywhere public, and if
you want a clean guarantee of secrecy, generate your own pair instead (see
"Generating your own VAPID keys" below) and use those instead of the ones
above.

Deploy the function:

```bash
supabase functions deploy send-push --no-verify-jwt
```

`--no-verify-jwt` is required here — the Database Webhook that calls this
function doesn't send a user login token (there isn't a logged-in user at
that point, it's the database calling out), so the function must accept
requests without one. This is safe: the function only ever reads
`app_settings`, `profiles`, and `push_subscriptions` with the service-role
key, and only sends push messages — it doesn't expose or accept arbitrary
data from the request beyond the webhook payload Supabase itself generates.

## Step 3 — Connect the database webhook

This is the wiring that makes step 2 actually fire when an order event
happens.

1. In your Supabase project dashboard: **Database → Webhooks → Create a new
   webhook**.
2. **Name**: `notify-push` (or anything you like).
3. **Table**: `notifications`.
4. **Events**: check only **Insert**.
5. **Type**: **Supabase Edge Functions**.
6. **Edge Function**: select `send-push`.
7. **HTTP Headers**: leave as default.
8. Save.

That's it — every time the existing triggers write a row into
`notifications` (which already happens automatically for every order event
covered in `NOTIFICATION_FRAMEWORK.md`), this webhook calls your function,
which looks up who should get it and pushes it to their devices.

## Step 4 — Try it

1. Open the app, sign in, click the bell icon.
2. Click **Enable** on the push row at the top of the notification panel.
3. Approve the browser's permission prompt.
4. Trigger a notification-worthy event — e.g. as Shop Staff, create a
   custom order priced above your approval threshold (Settings). As Owner
   or Manager, you should get a real push within a few seconds — try it
   with the app tab closed entirely to see the difference from the old
   in-app-only bell.

If nothing arrives, check, in order:
- Supabase Dashboard → **Edge Functions → send-push → Logs** — errors here
  usually mean a missing/misspelled secret from Step 2.
- Supabase Dashboard → **Database → Webhooks** — click your webhook to see
  its recent delivery attempts and their response codes.
- Confirm you clicked **Enable** in the app and approved the browser
  permission prompt — a subscribed device is required per person.

## Generating your own VAPID keys (optional, recommended eventually)

If you'd rather not rely on the keypair embedded in this document:

```bash
npx web-push generate-vapid-keys
```

This prints a fresh public/private pair. Use the public one in place of the
`VAPID_PUBLIC_KEY` constant near the top of `index.html`'s `<script>`
section, and use both in the `supabase secrets set` commands in Step 2
instead of the ones shown there.

## The iPhone caveat, one more time

A push notification will **not** appear for someone using this app in a
normal Safari tab on iPhone — Apple only allows web push for sites added to
the Home Screen (Settings → Share → Add to Home Screen). This isn't
something any code change can work around; it's an Apple platform
restriction. Android Chrome and any desktop browser work immediately, no
extra step needed.
