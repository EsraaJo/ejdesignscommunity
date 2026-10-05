import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: Record<string, unknown>, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
const htmlEntities: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" };
const escapeHtml = (value: string) => value.replace(/[&<>\"']/g, character => htmlEntities[character] || character);

Deno.serve(async request => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const emailFrom = Deno.env.get("EMAIL_FROM");
  if (!supabaseUrl || !anonKey || !serviceRoleKey || !resendApiKey || !emailFrom) return json({ error: "Email notification service is not configured" }, 503);
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);
  try {
    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false, autoRefreshToken: false } });
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) return json({ error: "Invalid session" }, 401);
    const body = await request.json().catch(() => ({}));
    const connectionId = typeof body.connectionId === "string" ? body.connectionId : "";
    if (!connectionId) return json({ error: "Connection request ID is required" }, 400);
    const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: connection, error: connectionError } = await admin.from("connections").select("id, requester_id, recipient_id, status").eq("id", connectionId).eq("requester_id", authData.user.id).eq("status", "pending").maybeSingle();
    if (connectionError) throw connectionError;
    if (!connection) return json({ error: "Pending request not found" }, 404);
    const [{ data: recipientData, error: recipientError }, { data: requesterData }] = await Promise.all([admin.auth.admin.getUserById(connection.recipient_id), admin.from("profiles").select("full_name").eq("id", authData.user.id).maybeSingle()]);
    if (recipientError) throw recipientError;
    const recipientEmail = recipientData.user?.email;
    if (!recipientEmail) return json({ error: "Recipient email is unavailable" }, 422);
    const requesterName = escapeHtml(requesterData?.full_name || "A community member");
    const result = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: "Bearer " + resendApiKey, "Content-Type": "application/json" },
      body: JSON.stringify({ from: emailFrom, to: [recipientEmail], subject: "You have a new connection request", html: "<p>Hello,</p><p><strong>" + requesterName + "</strong> sent you a connection request on EJ Designs Community.</p><p>Sign in to review it in My Network.</p>" }),
    });
    if (!result.ok) { console.error("Email provider rejected connection notification:", result.status, await result.text()); return json({ error: "Email provider could not send the notification" }, 502); }
    return json({ sent: true });
  } catch (error) { console.error("Connection request email failed:", error); return json({ error: "Unable to send connection request email" }, 500); }
});
