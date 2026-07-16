# Ticket Rail — Cake Order & Production System

A single-file web app for running order intake (2 shops) into one factory
production dashboard, with a live catalog, a separate custom-cake flow,
Google-only sign-in, owner-level user management, an audit trail, and
Excel/CSV exports. Runs entirely in the browser — backed by your own free
Supabase project.

## 1. Create your Supabase project (free tier)

1. Go to [supabase.com](https://supabase.com) → **New project**.
2. Pick any name/region and a database password (save it somewhere safe).
3. Wait ~2 minutes for it to spin up.

## 2. Run the database schema

1. In your Supabase project, open **SQL Editor → New query**.
2. Paste the entire contents of `schema.sql` and click **Run**.
3. This creates every table, role, catalog structure, the private photo
   storage bucket, row-level security policies, and audit-trail triggers —
   plus two demo shops and a starter 6-category catalog with example prices.
   Rename/edit all of it later from the app.

## 3. Turn on Google Sign-In

This app uses **Google (Gmail) OAuth as the only login method** — there's no
password system to manage. You need to connect a Google OAuth app to your
Supabase project once:

1. In **Google Cloud Console** ([console.cloud.google.com](https://console.cloud.google.com)):
   - Create a project (or use an existing one).
   - Go to **APIs & Services → OAuth consent screen** and set it up (External
     is fine for a small team; add your team's Gmail addresses as test users
     if it stays in "Testing" mode).
   - Go to **APIs & Services → Credentials → Create Credentials → OAuth
     client ID**, type **Web application**.
   - Under **Authorized redirect URIs**, add the callback URL Supabase shows
     you in the next step (looks like
     `https://<your-project-ref>.supabase.co/auth/v1/callback`).
   - Save, then copy the **Client ID** and **Client Secret**.
2. In your **Supabase project**: **Authentication → Providers → Google** →
   toggle it on, paste the Client ID and Client Secret, save.
3. In **Authentication → URL Configuration**, set the **Site URL** (and add
   **Redirect URLs**) to wherever you're hosting `index.html` — e.g. your
   GitHub Pages/Netlify URL, or `http://localhost` if you're just opening the
   file locally for now.

## 4. Get your API keys

1. In Supabase: **Project Settings → API**.
2. Copy the **Project URL** and the **`anon` `public`** key.

## 5. Open the app

1. Open `index.html` in a browser — double-click it, or host it anywhere
   static. No build step needed.
2. On first run it asks for your Supabase Project URL and anon key — paste
   them in. They're saved only in that browser's local storage.
3. Click **Sign in with Google**. **The very first person to ever sign in
   becomes the Owner automatically and is instantly active.** Everyone who
   signs in after that lands in a **"waiting for approval"** screen — the
   Owner activates them and assigns their real role + shop from **Manage
   Team**.

## 6. Set up your shops, catalog, and team

1. Go to **Shops** and rename/add your two retail locations.
2. Go to **Catalog** and edit the starter categories/items to match your real
   price sheet — every item stores its full-kg and half-kg price explicitly
   (never auto-calculated from one another, since that ratio isn't always
   exactly 2:1).
3. Have your Manager, Shop Staff, and Baker/Factory teammates sign in with
   their Gmail accounts, then activate each one from **Manage Team** and set
   their role + shop.
4. Optionally adjust the custom-order approval threshold in **Settings**.

## Roles, at a glance

| Role | Can do |
|---|---|
| **Owner** | Everything: orders, factory board, analytics, exports, catalog, team management (activate/suspend/remove/reassign anyone), shops, settings, delete orders |
| **Manager** | Same as Owner except cannot delete orders, cannot manage team accounts (activate/suspend/remove is Owner-only) |
| **Shop Staff** | Create/edit orders for their own shop only; locked out of editing cake specs once status reaches "Baking" (can still flag an order as rush); can move status through New → Confirmed → Cancelled |
| **Baker / Factory** | Sees every order from both shops on the Factory Board; can only change status — cannot edit order details |

Exact rules are enforced **in the database** (Postgres Row Level Security +
triggers in `schema.sql`), not just hidden in the UI.

## What's new in this version

- **Catalog module** — 6 categories → items → explicit full-kg/half-kg
  pricing, fully owner/manager-editable (not hardcoded). The order form shows
  category tabs → item grid → price auto-fills on selection. Quantities
  aren't locked to full/half kg — any fractional weight (0.5, 1, 1.5, 2…) is
  accepted; for anything besides exactly 0.5kg, the suggested price scales
  linearly off the per-kg price as a starting point, and staff can always
  hand-edit the final amount to match the real order.
- **Customized Cake add-on** — a separate "+ Customized Order" mode on the
  order form: cake description, design description, occasion/message, an
  estimated weight, up to 5 reference photos, and a manually-quoted price
  (never auto-calculated). Custom orders always show a **Custom** badge on
  the ticket, board card, and in exports so nobody mistakes one for a
  catalog item.
- **Approval gate for expensive custom orders** — any custom order quoted at
  or above the Owner-set threshold (Settings screen, default ₹5,000) is
  flagged "Needs approval" and is blocked from moving into "Baking" until an
  Owner or Manager approves or rejects it from the order's detail view.
- **Photo compression** — every reference photo is resized (max 1600px) and
  re-encoded as JPEG in the browser before upload, to keep well within
  Supabase's 1GB free storage tier.
- **Google Sign-In only** — no password system. New Gmail sign-ins land
  "pending" until the Owner activates them.
- **Owner-level user management** — Manage Team now shows every account's
  status, role, shop, and last-active time, with one-click Activate /
  Suspend / Remove, restricted to the Owner. Suspended/removed accounts lose
  all data access immediately via Row Level Security (every table checks the
  account is `active`); the app also polls every 45 seconds and signs a
  suspended/removed user out client-side. Historical orders stay attributed
  to removed accounts for audit purposes — nothing is deleted.

## A few honest limitations, worth knowing

- **"Instant" session invalidation**: suspending or removing someone blocks
  all their data access immediately (Row Level Security enforces this on
  every query, not just the UI), and the app force-signs them out within ~45
  seconds. True instant JWT revocation would require calling Supabase's
  admin API with a service-role key — that key can't safely live in a
  browser-only app, so it's not included here. If you need harder real-time
  revocation, that's a natural v3 addition (small backend function).
- **Removed accounts aren't deleted from Supabase Auth** — "Remove" revokes
  their access in this app (status → `removed`) and keeps their order
  history intact and attributed. To fully delete the underlying Google
  account link, use the Supabase dashboard's Authentication → Users screen.
- **Photo storage access** is authenticated-user-level, not shop-scoped —
  any active team member can view any custom order's reference photos (not
  just their own shop's). Flag if you'd want that tightened.

## Carried over from v1 — still deliberately deferred

- One-click **undo/redo** (the change log gives you a readable history instead)
- **Offline sync** at shop locations
- **Scheduled auto-export** (e.g. auto-email every Monday)
- Baker time-slot / overbooking prevention logic

## Notes on the free tier

Supabase's free tier includes the Postgres database, Auth, and 1GB of
Storage used here at no cost. If your project is inactive for a week it
pauses automatically — just open it in the Supabase dashboard to un-pause;
no data is lost.
