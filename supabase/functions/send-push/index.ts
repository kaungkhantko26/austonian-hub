import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const jwt = authHeader.replace(/^Bearer\s+/i, "");
    if (!jwt) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const callerClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: userData, error: userErr } = await callerClient.auth.getUser(jwt);
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const admin = createClient(supabaseUrl, serviceKey);

    const { data: profile } = await admin.from("profiles").select("is_admin").eq("id", userData.user.id).single();
    if (!profile?.is_admin) {
      return new Response(JSON.stringify({ error: "Administrator access required" }), { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const payload = await req.json();
    const title = String(payload.title || "").trim();
    const message = String(payload.body || "").trim();
    if (!title || !message) {
      return new Response(JSON.stringify({ error: "title and body are required" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    const tag = String(payload.tag || "austonian-update");
    const url = String(payload.url || "/#app");
    const targetUserId = payload.target_user_id || null;
    const targetAcademicLevel = payload.target_academic_level || null;
    const targetMajor = payload.target_major || null;
    const excludeUserId = payload.exclude_user_id || null;

    const { data: keys, error: keysErr } = await admin.from("push_vapid_keys").select("public_key,private_key,subject").eq("id", true).single();
    if (keysErr || !keys) {
      return new Response(JSON.stringify({ error: "Push notifications are not configured" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    webpush.setVapidDetails(keys.subject, keys.public_key, keys.private_key);

    let userIds: string[] | null = null;
    if (targetUserId) {
      userIds = [String(targetUserId)];
    } else if (targetAcademicLevel && targetAcademicLevel !== "all") {
      let profileQuery = admin.from("profiles").select("id").eq("academic_level", targetAcademicLevel);
      if (targetMajor) profileQuery = profileQuery.eq("major", targetMajor);
      const { data: matched } = await profileQuery;
      userIds = (matched || []).map((row: { id: string }) => row.id);
      if (!userIds.length) {
        return new Response(JSON.stringify({ sent: 0, removed: 0 }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
      }
    }

    let subsQuery = admin.from("push_subscriptions").select("id,user_id,endpoint,p256dh,auth");
    if (userIds) subsQuery = subsQuery.in("user_id", userIds);
    const { data: subs, error: subsErr } = await subsQuery;
    if (subsErr) throw subsErr;

    const targets = (subs || []).filter((sub: { user_id: string }) => sub.user_id !== excludeUserId);
    const notificationPayload = JSON.stringify({ title, body: message, tag, url });

    let sent = 0;
    const stale: number[] = [];
    await Promise.all(targets.map(async (sub: { id: number; endpoint: string; p256dh: string; auth: string }) => {
      try {
        await webpush.sendNotification({ endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } }, notificationPayload);
        sent++;
      } catch (err) {
        const statusCode = err?.statusCode;
        if (statusCode === 404 || statusCode === 410) stale.push(sub.id);
      }
    }));

    if (stale.length) await admin.from("push_subscriptions").delete().in("id", stale);

    return new Response(JSON.stringify({ sent, removed: stale.length }), { headers: { ...corsHeaders, "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : "Unexpected error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
