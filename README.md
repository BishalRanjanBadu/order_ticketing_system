# Cakes & Bakes — Ticket Rail

Order intake for two retail shops, syncing into one factory production
dashboard — with a live catalog, a separate custom-cake flow, Google-only
sign-in, owner-level user management, role-locked views, an audit trail,
session undo/redo, and Excel/CSV exports. Single HTML file, mobile-friendly,
backed by your own free Supabase project.

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
   Rename/edit all of it later from the app. Safe to re-run if you ever pull
   an updated `schema.sql`.

## 3. Turn on Google Sign-In

This app uses **Google (Gmail) OAuth as the only login method**.

1. In **Google Cloud Console** ([console.cloud.google.com](https://console.cloud.google.com)):
   - Create a project (or use an existing one).
   - Go to **APIs & Services → OAuth consent screen** and set it up.
   - Go to **APIs & Services → Credentials → Create Credentials → OAuth
     client ID**, type **Web application**.
   - Under **Authorized redirect URIs**, add the callback URL Supabase shows
     you in the next step (looks like
     `https://<your-project-ref>.supabase.co/auth/v1/callback`).
   - Save, then copy the **Client ID** and **Client Secret**.
2. In your **Supabase project**: **Authentication → Providers → Google** →
   toggle it on, paste the Client ID and Client Secret, save.
3. In **Authentication → URL Configuration**, set the **Site URL** (and add
   under **Redirect URLs**) to wherever you're hosting `index.html`.

**⚠️ Publish the consent screen — this is the #1 cause of "my staff can't
sign in even after I approved them."** While your OAuth consent screen is in
**Testing** mode, Google silently blocks any Gmail account that hasn't been
added as a test user — it never even reaches this app or Supabase, so
approving them here won't help. Fix it one of two ways:
- **Testing mode**: add every teammate's Gmail under **OAuth consent screen
  → Test users**, or
- **Production mode**: click **Publish App** on the consent screen (no
  Google review needed for the basic scopes this app uses).

## 4. Open the app

1. Open `index.html` — double-click it, or host it anywhere static (GitHub
   Pages, Netlify, Vercel). No build step needed.
2. The app ships with your Supabase Project URL + anon key already wired in
   (see `index.html` → `getConfig()`), so teammates can open the link and go
   straight to **Sign in with Google** — nobody has to paste API keys. If you
   ever move to a different Supabase project, update the `url`/`key` values
   in that function (or use the manual config screen for local testing —
   it still works and takes priority if you save keys there).
3. Click **Sign in with Google**. **The very first person to ever sign in
   becomes the Owner automatically and is instantly active.** Everyone who
   signs in after that lands on a **"waiting for approval"** screen (which
   auto-refreshes) — the Owner activates them and assigns their real role +
   shop from **Manage Team**.

## 5. Set up your shops, catalog, and team

1. Go to **Shops** and rename/add your two retail locations.
2. Go to **Catalog** and edit the starter categories/items to match your real
   price sheet — every item stores its full-kg and half-kg price explicitly.
3. Have your Manager, Shop Staff, and Baker teammates sign in with their
   Gmail accounts, then activate each one from **Manage Team**.
4. Optionally adjust the custom-order approval threshold in **Settings**.

## Roles, at a glance

| Role | Sees | Can do |
|---|---|---|
| **Owner** | Everything | Full access everywhere: orders, factory board, analytics, exports, catalog, team management, shops (including delete), settings, undo/redo, delete orders |
| **Manager** | Everything except Team/Settings | Same as Owner except cannot delete orders, cannot manage team accounts or reach Settings |
| **Shop Staff** | **Orders + New Order only** | Create/edit orders for their own shop; locked out of editing cake specs once status reaches "Baking"; can move an order through New → Confirmed → Cancelled, and mark it **Delivered** once it's Ready — but cannot touch Baking/Ready themselves (that's the factory's job) |
| **Baker / Factory** | **Factory Board only** | Sees every order from both shops; can only change status, and only through New → Confirmed → Baking → Ready — **cannot mark an order Delivered** (that's the shop's job when the customer picks it up) |

Every one of these rules is enforced **in the database** (Postgres Row Level
Security + triggers in `schema.sql`), not just hidden in the UI — a locked-
down role can't work around it by calling the API directly.

## What's new in this pass

- **Logo, properly rendered** — the source photo had the outer edges of the
  first and last letters clipped at the frame boundary; it's been rebuilt
  from the original pixels (not a font substitute) so "CAKES & BAKES" reads
  complete, and re-embedded throughout the app.
- **Factory board color coding** — each column now has its own tinted
  background wash, a colored top bar, and matching header text/count per
  production stage, not just a thin strip on each card.
- **Delete option for team accounts** (Owner-only, in Manage Team) —
  alongside the existing Suspend/Remove. This is a genuine hard delete, with
  tradeoffs spelled out below.
- **Delete option for catalog items** (Owner/Manager, in Catalog) — safe to
  use even on items with order history, since every order keeps its own
  snapshot of the item name/price at the time it was placed.
- **Billing: advance / balance / due-on-delivery** — every order now has an
  "Advance received" field with a live-computed balance. Tickets and factory
  board cards show a "₹X due" tag whenever a balance remains. Marking an
  order **Delivered** now opens a small billing-confirmation dialog (total /
  paid / balance, with an editable "amount collected now") instead of just
  flipping the status. Analytics gained a **Pending balance** stat, and
  exports gained **Advance Received** / **Balance Due** columns.
- **WhatsApp receipt** — a **Send receipt** button on any order (with a
  phone number) opens WhatsApp with the order details, delivery date, and
  billing summary pre-filled as a message — one tap to send, no cost, no
  setup. You're also asked right after creating an order with a phone number
  attached. See the limitations below for why this is "click to send"
  rather than fully automatic.
- **Redesigned background** — a subtle kraft-paper grain texture, bolder
  coral/lavender/butter ambient color pulled from your visiting card, and
  hand-drawn pastry doodles now appear across the sign-in screen, the
  sidebar, and empty states — not just as a one-off accent.

### From the previous pass (still in place)

- Search no longer loses focus while typing (only the ticket rail re-renders
  on each keystroke).
- Photos on every order, not just custom ones, with local download buttons
  (including "download all" for multi-photo orders).
- Session Undo / Redo / Clear, Owner-only, in **Settings**.
- Locked-down role views: Shop Staff sees Orders + New Order only and can
  hand off to Delivered but not touch Baking/Ready; Baker sees the Factory
  Board only and can run production but not mark Delivered.
- Owner can delete shops (blocked automatically if the shop still has orders
  — deactivate instead), and a shop's name frees up for reuse the moment
  it's deactivated or deleted.
- Proper mobile layout: a top app bar with a hamburger menu opens a slide-in
  nav drawer; the order modal goes full-screen; tables scroll horizontally;
  forms and filters stack to a single column.

## A few honest limitations, worth knowing

- **Deleting a team account is permanent and only removes their *app*
  profile** — their Google/Supabase Auth account itself isn't touched (that
  needs the Supabase dashboard). Their old orders stay on file but show as
  created by a deleted account instead of their name. If they sign in again
  later, the app detects the missing profile and quietly recreates a fresh
  **pending** account for them (safe defaults only — they can't grant
  themselves a role), so they're not permanently locked out, just back to
  square one for approval. If you just want to revoke someone's access
  without losing their name on history, use **Remove** instead — that's
  reversible and keeps attribution intact.
- **The WhatsApp receipt is "click to send," not automatic.** Supabase's
  free tier has no way to send SMS/WhatsApp messages on its own — that needs
  a paid provider (Twilio, or India-friendly options like MSG91/Gupshup)
  plus a small server-side function, since a provider API key can't safely
  live in browser code. The current version opens a pre-filled WhatsApp chat
  and a staff member taps Send — free, instant, zero setup. If you want it
  to fire automatically with no human in the loop, that's a v-next feature
  once you've picked and funded a provider.
- **Undo/redo is session-only and covers the highest-value actions** (order
  status/edits/approvals, catalog prices) — it doesn't cover every possible
  action (e.g. team role changes), and it resets when you reload the page.
  The permanent, complete record of every change is still the per-order
  **History** tab, which never resets.
- **"Instant" session invalidation** for suspended/removed accounts: Row
  Level Security blocks all their data access immediately, and the app
  force-signs them out within ~45 seconds — but true instant JWT revocation
  would need a service-role key, which can't safely live in a browser-only
  app.
- **Photo storage access** is authenticated-user-level, not shop-scoped —
  any active team member can view any order's reference photos.

## Still deliberately deferred

- **Offline sync** at shop locations
- **Fully automatic WhatsApp/SMS sending** (needs a paid provider — see above)
- **Scheduled auto-export** (e.g. auto-email every Monday)
- Baker time-slot / overbooking prevention logic

## Notes on the free tier

Supabase's free tier includes the Postgres database, Auth, and 1GB of
Storage used here at no cost. If your project is inactive for a week it
pauses automatically — just open it in the Supabase dashboard to un-pause;
no data is lost.
