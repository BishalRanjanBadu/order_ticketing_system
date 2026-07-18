# Notification Decision Framework

This is the reference for *why* each notification goes to *who*. If you ever
want to add a new notification, change who gets an existing one, or explain
the system to someone else on the team, start here — then make the matching
change in `schema.sql` (the `orders_notify()` / `profiles_notify()` trigger
functions).

## The core rule

> **A notification exists only if it's actionable by the person receiving
> it.** If a role can't do anything in response, they don't get pinged.

This is why, for example, Shop Staff don't get notified when an order enters
Baking — they can't act on that (only the Baker can), so it would just be
noise. But they *do* get notified when an order becomes Ready, because
that's the moment it becomes their job again (arrange pickup/delivery).

## Decision table

For every event, ask three questions in order:

1. **What happened?** (the trigger)
2. **Who can act on it right now?** (the audience — this is the only
   question that determines routing)
3. **What's the next action they'd take?** (shapes the message text, so the
   notification itself hints at what to do, not just what happened)

| # | Event (trigger) | Condition | Audience | Why this audience | Next action implied |
|---|---|---|---|---|---|
| 1 | Order created | (every order, any kind) | Baker | The factory wants visibility on everything coming in as early as possible, not just once a shop has finished confirming it — lets them plan capacity ahead of the order actually being ready to bake | Baker: aware early, can plan ahead |
| 2 | Order created | `order_kind = 'custom'` **and** quoted amount ≥ approval threshold | Owner, Manager | Only they can approve/reject a custom order | Open the order, approve or reject |
| 3 | Order created **or** updated | `is_priority` flips to `true` | Baker, Owner, Manager | Baker needs to reprioritize the queue; Owner/Manager want visibility on rush commitments | Baker: bump it up the queue. Owner/Manager: aware, no action required |
| 4 | Status → `ready` | (any order) | Shop Staff *(same shop only)*, Owner, Manager | Shop Staff must arrange pickup/delivery; Owner/Manager want completion visibility | Shop Staff: contact customer / prep handoff |
| 5 | `approval_status` → `approved` | (custom order) | Shop Staff *(same shop)*, the specific person who created it | The shop can now proceed; the creator gets a direct confirmation regardless of role | Move the order forward |
| 6 | `approval_status` → `rejected` | (custom order) | Shop Staff *(same shop)*, the specific person who created it | Same as above — they need to know it's blocked and probably follow up with the customer | Contact customer, re-quote, or cancel |
| 7 | New profile created | `status = 'pending'` (i.e. not the bootstrap first-ever Owner) | Owner only | Owner is the *only* role that can activate accounts — Manager deliberately can't | Go to Manage Team, assign role + shop |

**A note on row 1, since it bends the core rule above**: strictly, a
brand-new order isn't yet "actionable" by the Baker — it might still be
edited, or even cancelled, before it's confirmed. This one was changed
after real usage feedback: waiting until Confirmed meant the Baker found
out later than felt useful in practice, so early visibility won a
deliberate exception over strict actionability. Every other row still
follows the core rule as written.

## Why some obvious-seeming notifications are deliberately *absent*

| Event | Why it's not a notification |
|---|---|
| Status → `new`, for Shop Staff/Owner/Manager | The person creating the order already knows they just created it — pinging them about their own action is noise. (The Baker is the one exception — see row 1 above.) |
| Status → `baking` | Only the Baker can act during baking, and the Baker is the one who *set* that status — notifying them of their own action is noise. |
| Status → `delivered` | Terminal state, nothing left to action. (It does still show up in Analytics/Export — just not as a push.) |
| Manager sees "new teammate pending" | Manager can't activate accounts (Owner-only, by design — see the Roles table in the main README), so being told about it would be a dead end. |
| Baker sees billing/advance changes | Baker's permissions never touch billing fields — irrelevant to their job regardless of what changes. |
| Catalog price edits | Nobody's workflow is blocked or unblocked by a price change; it's a settings action, not an event in the order lifecycle. |

## Adding a new notification later

Walk through the same three questions before writing any code:

1. Name the trigger precisely (an insert? an update to a specific column? a
   specific value transition, like `old.x ≠ 'ready' AND new.x = 'ready'`?).
2. List every role that would *actually do something* in response. If the
   list is empty, stop — it's not a notification, it's just an audit-log
   entry (which every order already gets, permanently, in its History tab).
3. Decide the target shape:
   - **`role`** — broadcast to everyone with that role (e.g. all Bakers)
   - **`role_shop`** — broadcast to everyone with that role *at one shop*
     (e.g. Shop Staff at Shop A only)
   - **`user`** — one specific person (e.g. "the person who created this
     order")
4. Write the message so it front-loads the *decision*, not just the fact —
   "Custom order needs approval" beats "Order status changed."

Then add the call in `orders_notify()` (or wherever the underlying event
already fires) in `schema.sql`, following the pattern of the existing
`perform public.notify(...)` calls.

## Anti-patterns to avoid

- **Don't notify a role "just in case."** Every unnecessary notification
  trains people to stop reading the bell. If you're unsure whether a role
  needs one, leave it out — it's easy to add later once someone actually
  asks "why didn't I know about X?"
- **Don't duplicate what the History tab already does.** History is the
  permanent, complete audit trail of every field change on an order.
  Notifications are a *subset* of that, filtered down to what's urgent and
  actionable right now. If everything became a notification, the two would
  be redundant and the bell would be useless.
- **Don't make Owner the default catch-all.** It's tempting to just add
  Owner to every notification "to be safe." Resist it — Owner already gets
  the three that matter (approvals, rush orders, pending teammates); piling
  on more turns the one role who needs the clearest signal into the one
  with the most noise.
