<div align="center">

# 🍰 Ticket Rail
### Order & Production Management System for Multi-Location Bakeries

**A full-stack operations platform built to replace pen-and-paper order
tickets** — order intake, role-based production tracking, billing, and
real-time notifications for a two-shop bakery feeding one central factory.

[![Live Demo](https://img.shields.io/badge/demo-live-brightgreen?style=for-the-badge)](https://bishalranjanbadu.github.io/order_ticketing_system/)
[![Postgres](https://img.shields.io/badge/PostgreSQL-Supabase-3ECF8E?style=for-the-badge&logo=supabase&logoColor=white)](https://supabase.com)
[![JavaScript](https://img.shields.io/badge/JavaScript-ES6+-F7DF1E?style=for-the-badge&logo=javascript&logoColor=black)](#tech-stack)
[![PWA](https://img.shields.io/badge/Push-Web%20Push%20API-FF6B6B?style=for-the-badge)](#tech-stack)
[![License](https://img.shields.io/badge/license-MIT-blue?style=for-the-badge)](#license)

[Live Demo](https://bishalranjanbadu.github.io/order_ticketing_system/) ·
[Features](#key-features) ·
[Architecture](#architecture--engineering-decisions) ·
[Tech Stack](#tech-stack) ·
[Setup](#getting-started)

</div>

---

## Overview

Ticket Rail is a single-page operations platform that runs a real
multi-location bakery business end to end: two retail shops take orders,
one factory produces them, and every role — Owner, Manager, Shop Staff,
Baker — gets exactly the view and permissions their job needs, enforced
not just in the UI but at the database layer.

It started as a request to digitize a paper order rail. It grew into a
system with role-based production tracking, a live catalog, custom-order
approvals, billing, a permanent audit trail, real-time sync across every
open session, and genuine OS-level push notifications — all running on a
**single static HTML file** with zero build tooling, deployable to any
static host.

## Screenshots

> _Add screenshots of the Orders rail, Factory Board, and mobile view here
> — e.g. `docs/screenshot-orders.png`, `docs/screenshot-factory.png`._

```
docs/
├── screenshot-orders.png
├── screenshot-factory-board.png
├── screenshot-past-orders.png
└── screenshot-mobile.png
```

## Key Features

### Order Lifecycle & Production
- Full order pipeline — **New → Confirmed → Baking → Ready → Delivered**
  — visualized as a kanban-style **Factory Board**, color-coded by stage
- **Catalog module**: categories → items → explicit per-kg/half-kg
  pricing, editable without touching code
- **Custom cake orders** as a distinct flow — multi-photo upload
  (client-side compressed before storage), design notes, and an
  Owner/Manager approval gate that auto-triggers above a configurable
  price threshold
- **Past Orders archive**: Delivered/Cancelled orders roll off the active
  board automatically at the end of the day they're completed — no
  scheduled job, computed live — keeping day-to-day views uncluttered
  while nothing is ever lost (see [Architecture](#architecture--engineering-decisions))

### Role-Based Access Control
Four roles — **Owner, Manager, Shop Staff, Baker** — each see a different
app, not just a different theme:

| | Owner | Manager | Shop Staff | Baker |
|---|:---:|:---:|:---:|:---:|
| View & manage all orders | ✅ | ✅ | own shop | Factory Board only |
| Confirm / advance production | ✅ | ✅ | — | ✅ |
| Cancel an order | ✅ | ✅ | ✅ | — |
| Approve custom orders | ✅ | ✅ | — | — |
| Edit/restore an archived order | ✅ | view-only | view-only | — |
| Manage team, shops, settings | ✅ | — | — | — |

Every rule above is enforced with **Postgres Row Level Security and
database triggers** — not application-layer checks alone — so permissions
hold even against a direct API call.

### Real-Time & Notifications
- **Live sync across every open session** via Postgres logical
  replication (Supabase Realtime) — no polling, no manual refresh
- **In-app notification center** — swipe-to-dismiss, per-role targeting
  generated entirely by database triggers
- **Genuine push notifications** — lock-screen/OS-tray delivery via the
  Web Push API, a Service Worker, and a Supabase Edge Function, triggered
  automatically the instant a database event fires
- Two-tier control: a personal per-device mute, plus an Owner-level
  global kill switch

### Business Operations
- **Billing**: advance payments, auto-computed balance due, a delivery-time
  confirmation modal so nothing is handed over unbilled
- **WhatsApp receipts**: one tap opens a pre-filled customer message
- **Analytics**: revenue, order volume, and breakdowns by shop/status/weekday
- **Export**: CSV/Excel with quarter/month/year presets
- **Permanent audit trail** on every order, plus a session-scoped
  **undo/redo** for fast recovery from a wrong click
- **Google OAuth-only sign-in** with an Owner-gated approval queue for
  new accounts

## Architecture & Engineering Decisions

A few decisions worth calling out, since they're the parts that matter
more than the feature list:

**Security lives in the database, not just the UI.**
Every permission — who can edit what, when an order locks, who can
approve a custom order — is enforced with Postgres Row Level Security
policies and `BEFORE UPDATE` triggers. The frontend hides buttons a role
can't use, but the actual enforcement doesn't trust the frontend at all.

**No cron jobs, ever — state is computed, not scheduled.**
The Past Orders archive is the clearest example: rather than running a
scheduled job to "move" orders at midnight (a real failure mode — a
missed run leaves something silently stuck), whether an order counts as
"archived" is a live comparison between a stored timestamp and the
viewer's current date, recalculated on every render. There is nothing
that can fail to run.

**Push notifications, built on primitives, not a third-party SDK.**
The push pipeline is a Service Worker plus a Deno-based Supabase Edge
Function signing VAPID payloads directly against the Web Push protocol —
triggered by a Postgres database webhook the instant a notification row
is written. No push-as-a-service vendor, no polling.

**Single-file frontend, by design.**
No bundler, no framework, no `node_modules`. The entire client is one
HTML file with inline CSS/JS, using the Supabase JS client via CDN. It
deploys by uploading a file — to GitHub Pages, Netlify, or any static
host — and there is no build step to get wrong.

**A custom visual design system, not a component library.**
The interface (a "kraft paper and ticket rail" theme, down to a
hand-drawn cake-tier progress indicator used as the core status
visualization) was built from the bakery's own branding, in hand-written
CSS with no UI framework dependency.

## Tech Stack

| Layer | Technology |
|---|---|
| **Frontend** | Vanilla JavaScript (ES6+), HTML5, CSS3 — no framework, no build step |
| **Backend / Database** | [Supabase](https://supabase.com) — PostgreSQL, Row Level Security, Realtime, Storage |
| **Auth** | Google OAuth 2.0 via Supabase Auth |
| **Serverless Functions** | Supabase Edge Functions (Deno) |
| **Push Notifications** | Web Push API, VAPID, Service Workers |
| **Hosting** | Static hosting (GitHub Pages) |

## Project Structure

```
.
├── index.html                          # entire frontend — single file, no build step
├── sw.js                               # service worker (push notification delivery)
├── schema.sql                          # full database schema: tables, RLS, triggers
└── supabase/
    └── functions/
        └── send-push/
            └── index.ts                # Edge Function: sends Web Push on new notifications
```

## Getting Started

This app runs against your own free [Supabase](https://supabase.com)
project — no server to manage.

1. **Create a Supabase project**, then run `schema.sql` in the SQL Editor.
2. **Enable Google as an Auth provider** in Supabase and configure the
   OAuth consent screen in Google Cloud Console.
3. **Open `index.html`** — the Supabase connection is configured inline;
   host it anywhere static (GitHub Pages, Netlify, or locally).
4. *(Optional)* **Enable push notifications** by deploying the Edge
   Function and connecting the database webhook — see the setup notes in
   the repo for the full walkthrough.

The first Google account to sign in becomes the Owner automatically;
every account after that waits in an approval queue.

## Roadmap

- Offline-first support at shop locations via a local cache layer
- Scheduled/automated report delivery (e.g. a weekly email digest)
- Baker time-slot management to prevent production overbooking

## License

MIT — free to use, adapt, and learn from.

---

<div align="center">

Built to run a real two-location bakery's daily order flow, end to end.

</div>
