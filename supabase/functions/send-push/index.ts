// supabase/functions/send-push/index.ts
//
// Triggered by a Supabase Database Webhook on INSERT into public.notifications
// (configure the webhook in the dashboard — see PUSH_NOTIFICATIONS_SETUP.md).
// This function resolves who a notification is targeted at (same rules as
// the in-app bell: by exact person, by role, or by role+shop), looks up
// their registered devices, and sends each one a real Web Push message.
//
// Required secrets (set with `supabase secrets set ...`, see setup doc):
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY  (Supabase provides these
//     automatically to every Edge Function — you don't set them yourself)
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
const VAPID_SUBJECT = Deno.env.get("VAPID_SUBJECT") || "mailto:admin@example.com";

webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record; // the new notifications row
    if (!record) return new Response("no record", { status: 400 });

    // 1. Respect the Owner's global kill switch
    const { data: setting } = await admin
      .from("app_settings")
      .select("value")
      .eq("key", "push_notifications_enabled")
      .maybeSingle();
    if (setting && setting.value === false) {
      return new Response(JSON.stringify({ skipped: "push disabled globally" }), { status: 200 });
    }

    // 2. Resolve which active, push-enabled profiles this notification targets
    let profileIds: string[] = [];
    if (record.target_type === "user" && record.target_profile_id) {
      const { data } = await admin
        .from("profiles")
        .select("id")
        .eq("id", record.target_profile_id)
        .eq("status", "active")
        .eq("push_enabled", true);
      profileIds = (data || []).map((p) => p.id);
    } else if (record.target_type === "role" && record.target_role) {
      const { data } = await admin
        .from("profiles")
        .select("id")
        .eq("role", record.target_role)
        .eq("status", "active")
        .eq("push_enabled", true);
      profileIds = (data || []).map((p) => p.id);
    } else if (record.target_type === "role_shop" && record.target_role && record.target_shop_id) {
      const { data } = await admin
        .from("profiles")
        .select("id")
        .eq("role", record.target_role)
        .eq("shop_id", record.target_shop_id)
        .eq("status", "active")
        .eq("push_enabled", true);
      profileIds = (data || []).map((p) => p.id);
    }

    if (profileIds.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: "no matching active/opted-in profiles" }), { status: 200 });
    }

    // 3. Look up every device subscribed for those people
    const { data: subs } = await admin
      .from("push_subscriptions")
      .select("*")
      .in("profile_id", profileIds);

    if (!subs || subs.length === 0) {
      return new Response(JSON.stringify({ sent: 0, reason: "no devices subscribed" }), { status: 200 });
    }

    const payloadJson = JSON.stringify({
      id: record.id,
      title: record.title,
      body: record.body,
      order_id: record.order_id,
    });

    let sent = 0, failed = 0, cleaned = 0;
    for (const sub of subs) {
      const pushSubscription = {
        endpoint: sub.endpoint,
        keys: { p256dh: sub.p256dh, auth: sub.auth_key },
      };
      try {
        await webpush.sendNotification(pushSubscription, payloadJson);
        sent++;
      } catch (err: any) {
        failed++;
        // 404/410 means the browser has permanently invalidated this
        // subscription (uninstalled, permission revoked, etc) — clean it up
        // so we stop trying to send to a dead endpoint.
        if (err?.statusCode === 404 || err?.statusCode === 410) {
          await admin.from("push_subscriptions").delete().eq("id", sub.id);
          cleaned++;
        }
      }
    }

    return new Response(JSON.stringify({ sent, failed, cleaned }), { status: 200 });
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err?.message || String(err) }), { status: 500 });
  }
});
