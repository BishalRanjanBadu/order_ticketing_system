-- ============================================================================
-- CAKE ORDER MANAGEMENT SYSTEM — Supabase schema (v2)
-- Run this once in your Supabase project: SQL Editor → New query → paste → Run
-- Safe to re-run: uses "if not exists" / "or replace" / "drop policy if exists"
-- throughout, so re-running after edits won't duplicate anything.
-- ============================================================================

create extension if not exists pgcrypto;

-- ----------------------------------------------------------------------------
-- SHOPS
-- ----------------------------------------------------------------------------
create table if not exists public.shops (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.shops add column if not exists active boolean not null default true;
-- migration: earlier versions had a hard UNIQUE on name, which meant a
-- deactivated shop's name stayed "taken" forever and blocked re-adding it.
-- Drop that constraint (safe no-op if you're on a fresh install) and use a
-- partial unique index instead, scoped to active shops only.
alter table public.shops drop constraint if exists shops_name_key;
create unique index if not exists shops_name_active_idx on public.shops(name) where active;

-- ----------------------------------------------------------------------------
-- PROFILES  (one row per auth.users row; created automatically on Google sign-in)
-- role:   'owner' | 'manager' | 'shop_staff' | 'baker'
-- status: 'active' | 'pending' | 'suspended' | 'removed'
-- shop_id: only meaningful for 'shop_staff' — which shop they work at
-- ----------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null default '',
  full_name text not null default '',
  role text not null default 'shop_staff'
    check (role in ('owner','manager','shop_staff','baker')),
  status text not null default 'pending'
    check (status in ('active','pending','suspended','removed')),
  shop_id uuid references public.shops(id) on delete set null,
  created_at timestamptz not null default now(),
  last_active timestamptz not null default now()
);

-- Add columns if upgrading an existing v1 database
alter table public.profiles add column if not exists email text not null default '';
alter table public.profiles add column if not exists status text not null default 'active';
alter table public.profiles add column if not exists last_active timestamptz not null default now();
do $$ begin
  alter table public.profiles add constraint profiles_status_check check (status in ('active','pending','suspended','removed'));
exception when duplicate_object then null;
end $$;

-- Auto-create a profile row whenever someone signs in with Google for the first time.
-- The very first person to EVER sign in becomes 'owner' and is auto-activated
-- (this is the bootstrap step for whoever is setting the system up).
-- Everyone after that lands as 'pending' — the Owner must activate them and
-- assign a real role + shop from the "Manage Team" screen before they can do anything.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  is_first boolean;
  gmail_name text;
begin
  select not exists (select 1 from public.profiles) into is_first;
  gmail_name := coalesce(
    new.raw_user_meta_data->>'full_name',
    new.raw_user_meta_data->>'name',
    split_part(new.email,'@',1)
  );

  insert into public.profiles (id, email, full_name, role, status)
  values (
    new.id,
    new.email,
    gmail_name,
    case when is_first then 'owner' else 'shop_staff' end,
    case when is_first then 'active' else 'pending' end
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ----------------------------------------------------------------------------
-- CATALOG — categories and items, owner/manager-editable, never hardcoded
-- ----------------------------------------------------------------------------
create table if not exists public.catalog_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.catalog_items (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.catalog_categories(id) on delete cascade,
  name text not null,
  -- both prices are stored explicitly (never derived from one another) because
  -- the relationship between full-kg and half-kg pricing isn't guaranteed to
  -- stay a clean 2:1 ratio for every item on the sheet.
  price_full_kg numeric(10,2) not null default 0,
  price_half_kg numeric(10,2) not null default 0,
  sort_order int not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists idx_catalog_items_category on public.catalog_items(category_id);

-- ----------------------------------------------------------------------------
-- APP SETTINGS — small owner-editable key/value config (e.g. approval threshold)
-- ----------------------------------------------------------------------------
create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now()
);
insert into public.app_settings (key, value)
  values ('custom_order_approval_threshold', '5000')
  on conflict (key) do nothing;

-- ----------------------------------------------------------------------------
-- ORDERS
-- ----------------------------------------------------------------------------
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  shop_id uuid not null references public.shops(id),
  customer_name text not null,
  customer_phone text not null default '',

  -- catalog vs. custom
  order_kind text not null default 'catalog' check (order_kind in ('catalog','custom')),
  catalog_item_id uuid references public.catalog_items(id) on delete set null,
  catalog_category_snapshot text not null default '',  -- captured at order time so
  catalog_item_snapshot text not null default '',      -- renames/removals later don't rewrite history
  weight_kg numeric(5,2) not null default 1,

  cake_type text not null default '',   -- for custom orders: freeform cake description
  size text not null default '',
  flavor text not null default '',
  celebration_type text not null default '',
  design_notes text not null default '',        -- doubles as "design description" for custom orders
  message_on_cake text not null default '',      -- doubles as occasion/message text
  reference_photos text[] not null default '{}', -- storage paths, custom orders only, up to a few images
  is_priority boolean not null default false,

  order_date date not null default current_date,
  delivery_date date not null,
  delivery_time time,
  status text not null default 'new'
    check (status in ('new','confirmed','baking','ready','delivered','cancelled')),
  amount numeric(10,2) not null default 0,
  advance_amount numeric(10,2) not null default 0,

  -- custom-order approval gate
  approval_status text not null default 'not_required'
    check (approval_status in ('not_required','pending','approved','rejected')),
  approved_by uuid references public.profiles(id) on delete set null,
  approved_at timestamptz,

  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Add columns if upgrading an existing v1 database
alter table public.orders add column if not exists order_kind text not null default 'catalog';
alter table public.orders add column if not exists catalog_item_id uuid references public.catalog_items(id) on delete set null;
alter table public.orders add column if not exists catalog_category_snapshot text not null default '';
alter table public.orders add column if not exists catalog_item_snapshot text not null default '';
alter table public.orders add column if not exists weight_kg numeric(5,2) not null default 1;
alter table public.orders add column if not exists reference_photos text[] not null default '{}';
alter table public.orders add column if not exists approval_status text not null default 'not_required';
alter table public.orders add column if not exists approved_by uuid references public.profiles(id);
alter table public.orders add column if not exists approved_at timestamptz;
alter table public.orders add column if not exists advance_amount numeric(10,2) not null default 0;
do $$ begin
  alter table public.orders add constraint orders_kind_check check (order_kind in ('catalog','custom'));
exception when duplicate_object then null; end $$;
do $$ begin
  alter table public.orders add constraint orders_approval_check check (approval_status in ('not_required','pending','approved','rejected'));
exception when duplicate_object then null; end $$;
-- migration: allow deleting a team member's account without being blocked by
-- (or silently orphaning) orders they created/approved — the order just
-- keeps its snapshot data and loses the "created/approved by" link.
alter table public.orders drop constraint if exists orders_created_by_fkey;
alter table public.orders add constraint orders_created_by_fkey foreign key (created_by) references public.profiles(id) on delete set null;
alter table public.orders drop constraint if exists orders_approved_by_fkey;
alter table public.orders add constraint orders_approved_by_fkey foreign key (approved_by) references public.profiles(id) on delete set null;

create index if not exists idx_orders_shop on public.orders(shop_id);
create index if not exists idx_orders_status on public.orders(status);
create index if not exists idx_orders_delivery on public.orders(delivery_date);
create index if not exists idx_orders_kind on public.orders(order_kind);

-- ----------------------------------------------------------------------------
-- ORDER HISTORY  (append-only audit trail — never updated or deleted)
-- ----------------------------------------------------------------------------
create table if not exists public.order_history (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  changed_by uuid references public.profiles(id) on delete set null,
  change_type text not null,        -- 'created' | 'updated' | 'status_changed' | 'approval_changed'
  field_changed text,
  old_value text,
  new_value text,
  changed_at timestamptz not null default now()
);
alter table public.order_history drop constraint if exists order_history_changed_by_fkey;
alter table public.order_history add constraint order_history_changed_by_fkey foreign key (changed_by) references public.profiles(id) on delete set null;

create index if not exists idx_history_order on public.order_history(order_id);

-- ----------------------------------------------------------------------------
-- HELPER FUNCTIONS  (security definer so RLS policies can call them
-- without recursively re-checking RLS on profiles)
-- ----------------------------------------------------------------------------
create or replace function public.my_role()
returns text
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.my_shop()
returns uuid
language sql stable security definer set search_path = public
as $$
  select shop_id from public.profiles where id = auth.uid();
$$;

create or replace function public.my_status()
returns text
language sql stable security definer set search_path = public
as $$
  select status from public.profiles where id = auth.uid();
$$;

create or replace function public.approval_threshold()
returns numeric
language sql stable security definer set search_path = public
as $$
  select coalesce((select value from public.app_settings where key = 'custom_order_approval_threshold')::text::numeric, 999999999);
$$;

-- ----------------------------------------------------------------------------
-- TRIGGER: on insert, auto-set approval_status for custom orders that
-- clear the owner-configured price threshold
-- ----------------------------------------------------------------------------
create or replace function public.set_custom_order_approval()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.order_kind = 'custom' then
    if new.amount >= public.approval_threshold() then
      new.approval_status := 'pending';
    else
      new.approval_status := 'not_required';
    end if;
  else
    new.approval_status := 'not_required';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_set_custom_approval on public.orders;
create trigger trg_set_custom_approval
  before insert on public.orders
  for each row execute function public.set_custom_order_approval();

-- ----------------------------------------------------------------------------
-- TRIGGER: enforce who may change what on an order
--   owner / manager : can change anything, any time, including approvals
--   baker           : can ONLY change status, and only through the production
--                      stages (new→confirmed→baking→ready) — NOT the final
--                      "delivered" step, which belongs to the shop
--   shop_staff      : can edit their own shop's orders, but only while
--                      status is 'new' or 'confirmed' (locked once baking
--                      starts); may set status to new/confirmed/cancelled/
--                      delivered — i.e. intake and hand-off, not the factory's
--                      internal baking/ready stages; may always raise the
--                      priority flag
--   EVERYONE: a custom order stuck at approval_status='pending' cannot be
--             moved into 'baking' until Owner/Manager approves it.
-- ----------------------------------------------------------------------------
create or replace function public.enforce_order_edit_rules()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  role text := public.my_role();
  non_status_changed boolean;    -- any field besides status/is_priority/approval
  locked_fields_changed boolean; -- non_status_changed, excluding is_priority
  approval_changed boolean;
begin
  non_status_changed :=
    (old.shop_id, old.customer_name, old.customer_phone, old.cake_type, old.size,
     old.flavor, old.celebration_type, old.design_notes, old.message_on_cake,
     old.is_priority, old.delivery_date, old.delivery_time, old.amount, old.advance_amount,
     old.order_kind, old.catalog_item_id, old.weight_kg, old.reference_photos)
    is distinct from
    (new.shop_id, new.customer_name, new.customer_phone, new.cake_type, new.size,
     new.flavor, new.celebration_type, new.design_notes, new.message_on_cake,
     new.is_priority, new.delivery_date, new.delivery_time, new.amount, new.advance_amount,
     new.order_kind, new.catalog_item_id, new.weight_kg, new.reference_photos);

  locked_fields_changed :=
    (old.shop_id, old.customer_name, old.customer_phone, old.cake_type, old.size,
     old.flavor, old.celebration_type, old.design_notes, old.message_on_cake,
     old.delivery_date, old.delivery_time, old.amount,
     old.order_kind, old.catalog_item_id, old.weight_kg, old.reference_photos)
    is distinct from
    (new.shop_id, new.customer_name, new.customer_phone, new.cake_type, new.size,
     new.flavor, new.celebration_type, new.design_notes, new.message_on_cake,
     new.delivery_date, new.delivery_time, new.amount,
     new.order_kind, new.catalog_item_id, new.weight_kg, new.reference_photos);

  approval_changed := old.approval_status is distinct from new.approval_status;

  -- a pending custom order can't reach the factory queue until approved
  if new.status = 'baking' and old.status <> 'baking' and new.approval_status = 'pending' then
    raise exception 'This custom order needs Owner/Manager approval before it can start baking';
  end if;

  if approval_changed and role not in ('owner','manager') then
    raise exception 'Only Owner/Manager can approve or reject a custom order';
  end if;

  if role in ('owner','manager') then
    null; -- unrestricted
  elsif role = 'baker' then
    if non_status_changed then
      raise exception 'Bakers can only update order status, not order details';
    end if;
    if new.status = 'delivered' and old.status <> 'delivered' then
      raise exception 'Only Shop Staff/Owner/Manager can mark an order delivered';
    end if;
  elsif role = 'shop_staff' then
    if old.shop_id <> public.my_shop() then
      raise exception 'You can only edit orders for your own shop';
    end if;
    if locked_fields_changed and old.status not in ('new','confirmed') then
      raise exception 'This order is locked — production has already started';
    end if;
    if new.status not in ('new','confirmed','cancelled','delivered') and old.status <> new.status then
      raise exception 'Only Baker/Factory can move an order into baking/ready';
    end if;
    if new.status = 'delivered' and old.status not in ('ready','delivered') then
      raise exception 'An order can only be marked delivered once it is ready';
    end if;
  else
    raise exception 'Not authorized to edit orders';
  end if;

  if approval_changed and new.approval_status = 'approved' then
    new.approved_by := auth.uid();
    new.approved_at := now();
  end if;

  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_enforce_order_edit on public.orders;
create trigger trg_enforce_order_edit
  before update on public.orders
  for each row execute function public.enforce_order_edit_rules();

-- ----------------------------------------------------------------------------
-- TRIGGER: log every insert/update to order_history (audit trail)
-- ----------------------------------------------------------------------------
create or replace function public.log_order_insert()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  insert into public.order_history (order_id, changed_by, change_type, field_changed, old_value, new_value)
  values (new.id, auth.uid(), 'created', null, null,
    case when new.order_kind = 'custom' then 'Custom order created' else 'Order created' end);
  return new;
end;
$$;

drop trigger if exists trg_log_order_insert on public.orders;
create trigger trg_log_order_insert
  after insert on public.orders
  for each row execute function public.log_order_insert();

create or replace function public.log_order_update()
returns trigger
language plpgsql security definer set search_path = public
as $$
declare
  cols text[] := array['shop_id','customer_name','customer_phone','cake_type','size',
                        'flavor','celebration_type','design_notes','message_on_cake',
                        'is_priority','delivery_date','delivery_time','status','amount',
                        'advance_amount','weight_kg','approval_status'];
  c text;
  old_json jsonb := to_jsonb(old);
  new_json jsonb := to_jsonb(new);
begin
  foreach c in array cols loop
    if old_json->>c is distinct from new_json->>c then
      insert into public.order_history (order_id, changed_by, change_type, field_changed, old_value, new_value)
      values (
        new.id, auth.uid(),
        case when c = 'status' then 'status_changed'
             when c = 'approval_status' then 'approval_changed'
             else 'updated' end,
        c, old_json->>c, new_json->>c
      );
    end if;
  end loop;
  return new;
end;
$$;

drop trigger if exists trg_log_order_update on public.orders;
create trigger trg_log_order_update
  after update on public.orders
  for each row execute function public.log_order_update();

-- ----------------------------------------------------------------------------
-- TRIGGER: touch last_active whenever a profile row is read via RPC is not
-- possible (SELECT can't trigger); last_active is instead updated by the app
-- right after sign-in (see index.html). No DB trigger needed for that.
-- ----------------------------------------------------------------------------

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================
alter table public.shops enable row level security;
alter table public.profiles enable row level security;
alter table public.orders enable row level security;
alter table public.order_history enable row level security;
alter table public.catalog_categories enable row level security;
alter table public.catalog_items enable row level security;
alter table public.app_settings enable row level security;

-- SHOPS: any signed-in ACTIVE user can read; owner/manager can add/rename/
-- deactivate; only the OWNER can hard-delete a shop record
drop policy if exists shops_select on public.shops;
create policy shops_select on public.shops for select
  using (auth.uid() is not null and public.my_status() = 'active');

drop policy if exists shops_write on public.shops;
create policy shops_write on public.shops for insert
  with check (public.my_status() = 'active' and public.my_role() in ('owner','manager'));

drop policy if exists shops_update on public.shops;
create policy shops_update on public.shops for update
  using (public.my_status() = 'active' and public.my_role() in ('owner','manager'))
  with check (public.my_status() = 'active' and public.my_role() in ('owner','manager'));

drop policy if exists shops_delete on public.shops;
create policy shops_delete on public.shops for delete
  using (public.my_status() = 'active' and public.my_role() = 'owner');

-- PROFILES: everyone signed in can read all profiles (needed for name lookups,
-- the pending/suspended screen, and the owner's user-management panel) —
-- regardless of their own status, since a pending/suspended user still needs
-- to read their OWN row to see why they're locked out.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select
  using (auth.uid() is not null);

-- a user may update their own name / last_active, but NOT their own role,
-- shop, or status (that would let anyone self-promote or un-suspend)
drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update
  using (id = auth.uid())
  with check (id = auth.uid() and role = public.my_role() and status = public.my_status()
              and shop_id is not distinct from public.my_shop());

-- only the OWNER manages other people's accounts (per spec: owner-level user management)
drop policy if exists profiles_update_owner on public.profiles;
create policy profiles_update_owner on public.profiles for update
  using (public.my_status() = 'active' and public.my_role() = 'owner')
  with check (public.my_status() = 'active' and public.my_role() = 'owner');

-- self-heal insert: normally handle_new_user() creates a profile automatically
-- on first-ever Google sign-in. But if an Owner hard-deletes someone's profile
-- (see profiles_delete below) and that person signs in again later, their
-- auth.users row already exists so that trigger won't fire again — this
-- policy lets the app recreate a safe, minimal profile for them client-side
-- instead of leaving them stuck. Hardcoded-safe defaults only: nobody can
-- use this to hand themselves an elevated role or an active/owner status.
drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles for insert
  with check (id = auth.uid() and role = 'shop_staff' and status = 'pending' and shop_id is null);

-- only the OWNER can permanently delete an account (vs. Suspend/Remove,
-- which just revoke access and keep the person attributed on old orders)
drop policy if exists profiles_delete on public.profiles;
create policy profiles_delete on public.profiles for delete
  using (public.my_status() = 'active' and public.my_role() = 'owner' and id <> auth.uid());

-- CATALOG: any active signed-in user can read (needed for the order form);
-- only owner/manager can write
drop policy if exists catalog_categories_select on public.catalog_categories;
create policy catalog_categories_select on public.catalog_categories for select
  using (auth.uid() is not null and public.my_status() = 'active');
drop policy if exists catalog_categories_write on public.catalog_categories;
create policy catalog_categories_write on public.catalog_categories for all
  using (public.my_status() = 'active' and public.my_role() in ('owner','manager'))
  with check (public.my_status() = 'active' and public.my_role() in ('owner','manager'));

drop policy if exists catalog_items_select on public.catalog_items;
create policy catalog_items_select on public.catalog_items for select
  using (auth.uid() is not null and public.my_status() = 'active');
drop policy if exists catalog_items_write on public.catalog_items;
create policy catalog_items_write on public.catalog_items for all
  using (public.my_status() = 'active' and public.my_role() in ('owner','manager'))
  with check (public.my_status() = 'active' and public.my_role() in ('owner','manager'));

-- APP SETTINGS: any active user can read (order form needs the threshold... actually
-- only owner/manager act on it, but harmless to let everyone read); only owner writes
drop policy if exists app_settings_select on public.app_settings;
create policy app_settings_select on public.app_settings for select
  using (auth.uid() is not null and public.my_status() = 'active');
drop policy if exists app_settings_write on public.app_settings;
create policy app_settings_write on public.app_settings for all
  using (public.my_status() = 'active' and public.my_role() = 'owner')
  with check (public.my_status() = 'active' and public.my_role() = 'owner');

-- ORDERS
drop policy if exists orders_select on public.orders;
create policy orders_select on public.orders for select
  using (
    public.my_status() = 'active' and (
      public.my_role() in ('owner','manager','baker')
      or (public.my_role() = 'shop_staff' and shop_id = public.my_shop())
    )
  );

drop policy if exists orders_insert on public.orders;
create policy orders_insert on public.orders for insert
  with check (
    public.my_status() = 'active' and (
      public.my_role() in ('owner','manager')
      or (public.my_role() = 'shop_staff' and shop_id = public.my_shop())
    )
  );

drop policy if exists orders_update on public.orders;
create policy orders_update on public.orders for update
  using (
    public.my_status() = 'active' and (
      public.my_role() in ('owner','manager','baker')
      or (public.my_role() = 'shop_staff' and shop_id = public.my_shop())
    )
  )
  with check (
    public.my_status() = 'active' and (
      public.my_role() in ('owner','manager','baker')
      or (public.my_role() = 'shop_staff' and shop_id = public.my_shop())
    )
  );

drop policy if exists orders_delete on public.orders;
create policy orders_delete on public.orders for delete
  using (public.my_status() = 'active' and public.my_role() = 'owner');

-- ORDER HISTORY: read-only for anyone who can see the parent order; never editable
drop policy if exists history_select on public.order_history;
create policy history_select on public.order_history for select
  using (
    public.my_status() = 'active' and
    exists (select 1 from public.orders o where o.id = order_history.order_id)
  );
-- inserts happen only via the security-definer trigger functions above,
-- so no insert/update/delete policy is granted to regular roles.

-- ============================================================================
-- STORAGE — bucket + policies for custom-cake reference photos
-- ============================================================================
insert into storage.buckets (id, name, public)
  values ('cake-references', 'cake-references', false)
  on conflict (id) do nothing;

drop policy if exists cake_refs_select on storage.objects;
create policy cake_refs_select on storage.objects for select
  using (bucket_id = 'cake-references' and auth.uid() is not null and public.my_status() = 'active');

drop policy if exists cake_refs_insert on storage.objects;
create policy cake_refs_insert on storage.objects for insert
  with check (
    bucket_id = 'cake-references' and public.my_status() = 'active'
    and public.my_role() in ('owner','manager','shop_staff')
  );

drop policy if exists cake_refs_delete on storage.objects;
create policy cake_refs_delete on storage.objects for delete
  using (bucket_id = 'cake-references' and public.my_status() = 'active' and public.my_role() = 'owner');

-- ============================================================================
-- SEED DATA — shops + the 6-category catalog structure (edit prices freely
-- afterwards from the app's "Catalog" screen — nothing here is hardcoded
-- into the app, it's just a starting price sheet)
-- ============================================================================
insert into public.shops (name) values ('Shop A'), ('Shop B')
  on conflict (name) where active do nothing;

insert into public.catalog_categories (name, sort_order) values
  ('Normal', 1), ('Chocolate', 2), ('Sweets Filling', 3),
  ('Fruits', 4), ('Dry Fruit', 5), ('Fondant', 6)
  on conflict (name) do nothing;

-- example starter items — replace prices/names to match your real price sheet
insert into public.catalog_items (category_id, name, price_full_kg, price_half_kg, sort_order)
select c.id, i.name, i.pf, i.ph, i.sort
from public.catalog_categories c
join (values
  ('Normal','Vanilla Sponge',450,225,1),
  ('Normal','Butterscotch',480,240,2),
  ('Chocolate','Chocolate Truffle',550,275,1),
  ('Chocolate','Dark Chocolate Fudge',600,300,2),
  ('Sweets Filling','Rasmalai Cake',650,330,1),
  ('Sweets Filling','Gulab Jamun Fusion',650,330,2),
  ('Fruits','Fresh Fruit Cake',600,300,1),
  ('Fruits','Pineapple Delight',520,260,2),
  ('Dry Fruit','Dry Fruit Special',700,360,1),
  ('Fondant','Fondant Character Cake',900,470,1),
  ('Fondant','Fondant Tiered Cake',1000,520,2)
) as i(cat, name, pf, ph, sort) on i.cat = c.name
on conflict do nothing;
