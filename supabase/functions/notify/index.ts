// Israeli MBA Network: sends the app's emails, through Gmail (SMTP) or Resend.
//
//   { action: "join-request" }            -> emails the admins about the caller's pending request (with Approve and
//                                            Decline buttons), and tells the applicant their request is waiting
//   { action: "review-info", member, key } -> no login: who an emailed Approve/Decline button is about
//   { action: "review", member, key, approve } -> no login: records the decision from the emailed button, once
//   { action: "welcome", member: "<id>" } -> emails an approved member their welcome email (admins only)
//   { action: "intro", intro: "<id>" }    -> emails the recipient of the caller's new intro request
//   { action: "intro-accepted", intro: "<id>" } -> emails the requester that the caller accepted, with how to reach them
//
// The page calls this right after the matching database call. Every check is done here again
// with the caller's login, and each email is sent at most once (admin_notified_at / welcome_sent_at),
// so calling it twice, or calling it without the right status, does nothing.
//
// Secrets (Supabase dashboard -> Edge Functions -> Secrets). Set either the SMTP ones (e.g. a Gmail account)
// or RESEND_API_KEY. If SMTP_HOST is set, SMTP is used.
//   SMTP_HOST       e.g. smtp.gmail.com     SMTP_PORT  465
//   SMTP_USER       the Gmail address       SMTP_PASSWORD  a Gmail app password (not the normal password)
//   RESEND_API_KEY  key from resend.com
//   FROM_EMAIL      e.g. "Israeli MBA Network <you@gmail.com>" (with Gmail it must be SMTP_USER's address)
//   ADMIN_EMAILS    comma-separated, who gets "new request" emails
//   APP_URL         the site's address, e.g. https://neder-nesel.github.io/israeli-mba-network/
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "npm:@supabase/supabase-js@2.119.0";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const NETWORK = "Israeli MBA Network";
const env = (k: string) => Deno.env.get(k) ?? "";
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const esc = (s: unknown) =>
  String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));

async function send(to: string[], subject: string, html: string, replyTo?: string) {
  if (env("SMTP_HOST")) {
    // Port 465 (TLS). Supabase Edge Functions can't open ports 25 or 587.
    const client = new SMTPClient({
      connection: {
        hostname: env("SMTP_HOST"), port: Number(env("SMTP_PORT") || 465), tls: true,
        auth: { username: env("SMTP_USER"), password: env("SMTP_PASSWORD") },
      },
    });
    try {
      await client.send({ from: env("FROM_EMAIL"), to, subject, content: "auto", html, ...(replyTo ? { replyTo } : {}) });
    } finally {
      await client.close();
    }
    return;
  }
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${env("RESEND_API_KEY")}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: env("FROM_EMAIL"), to, subject, html, ...(replyTo ? { reply_to: replyTo } : {}) }),
  });
  if (!r.ok) throw new Error(`resend ${r.status}: ${await r.text()}`);
}

// The official welcome email, sent once per member (welcome_sent_at).
async function sendWelcome(admin: any, memberId: string) {
  const { data: m } = await admin.from("members")
    .update({ welcome_sent_at: new Date().toISOString() })
    .eq("id", memberId).eq("status", "approved").is("welcome_sent_at", null)
    .select("first_name").maybeSingle();
  if (!m) return false;
  const { data: c } = await admin.from("member_contacts").select("email").eq("member_id", memberId).single();
  const html = `
    <div style="font-family:Arial,sans-serif;font-size:15px;line-height:1.5;color:#161A26;max-width:560px">
      <h2 style="margin:0 0 12px">Welcome to ${NETWORK}, ${esc(m.first_name)}!</h2>
      <p>Your request to join has been approved. You're now an official member of ${NETWORK}, the network of Israeli MBA students and alumni in the US.</p>
      <p style="margin-bottom:4px"><b>What you can do now:</b></p>
      <ul style="margin-top:0">
        <li>Search for Israeli MBAs by school, company or industry</li>
        <li>Star the people you want to follow up with, and ask for warm intros</li>
        <li>Keep your profile current, so others can find you</li>
      </ul>
      <p>Log in any time at <a href="${esc(env("APP_URL"))}">${NETWORK}</a> with ${esc(c?.email)} and your password.</p>
      <p>Welcome aboard,<br>The ${NETWORK} team</p>
    </div>`;
  try {
    await send([c!.email], `You're in: welcome to ${NETWORK}`, html);
  } catch (e) {
    await admin.from("members").update({ welcome_sent_at: null }).eq("id", memberId);
    throw e;
  }
  return true;
}

// Approve / Decline from the admin email. The key is the request's private one-time review key.
async function review(admin: any, body: { action?: string; member?: string; key?: string; approve?: boolean }) {
  if (!body.member || !body.key) return json({ ok: false, error: "invalid" }, 400);
  const { data: t } = await admin.from("review_tokens").select("token").eq("member_id", body.member).maybeSingle();
  const { data: m } = await admin.from("members").select("first_name,last_name,headline,status").eq("id", body.member).maybeSingle();
  if (!m) return json({ ok: false, error: "invalid" }, 404);
  if (!t || t.token !== body.key) {
    return json(m.status !== "pending" ? { ok: false, error: "already-decided", status: m.status, first: m.first_name } : { ok: false, error: "invalid" }, 403);
  }
  if (body.action === "review-info") {
    const { data: s } = await admin.from("member_schools").select("school,class_year").eq("member_id", body.member).order("sort").limit(1).maybeSingle();
    return json({ ok: true, first: m.first_name, last: m.last_name, headline: m.headline, school: s?.school ?? "", classYear: s?.class_year ?? null });
  }
  const status = body.approve ? "approved" : "declined";
  const { data: done } = await admin.from("members")
    .update({ status, decided_at: new Date().toISOString(), updated_at: new Date().toISOString() })
    .eq("id", body.member).eq("status", "pending").select("id").maybeSingle();
  if (!done) return json({ ok: false, error: "already-decided", status: m.status, first: m.first_name }, 409);
  await admin.from("review_tokens").delete().eq("member_id", body.member);
  let welcomed = false;
  if (body.approve) { try { welcomed = await sendWelcome(admin, body.member); } catch (e) { console.error(e); } }
  return json({ ok: true, status, first: m.first_name, welcomed });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: { action?: string; member?: string; intro?: string; key?: string; approve?: boolean };
  try { body = await req.json(); } catch { return json({ ok: false, error: "bad-request" }, 400); }

  // Emailed Approve/Decline buttons work without logging in: the private review key is the permission.
  if (body.action === "review" || body.action === "review-info") {
    try { return await review(createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY")), body); }
    catch (e) { console.error(e); return json({ ok: false, error: "failed" }, 500); }
  }

  // Who is calling? (verified from their login token)
  const asCaller = createClient(env("SUPABASE_URL"), env("SUPABASE_ANON_KEY"), {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const { data: { user } } = await asCaller.auth.getUser();
  if (!user) return json({ ok: false, error: "not-logged-in" }, 401);
  const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"));

  try {
    if (body.action === "join-request") {
      // Only the caller's own request, only while pending, only once.
      const { data: m } = await admin.from("members")
        .update({ admin_notified_at: new Date().toISOString() })
        .eq("id", user.id).eq("status", "pending").is("admin_notified_at", null)
        .select("first_name,last_name,headline,location,industry,linkedin_url,join_answer,signup_source").maybeSingle();
      if (!m) return json({ ok: true, sent: false });
      const { data: c } = await admin.from("member_contacts").select("email,phone").eq("member_id", user.id).single();
      const { data: s } = await admin.from("member_schools").select("school,class_year").eq("member_id", user.id).order("sort").limit(1).maybeSingle();
      const { data: k } = await admin.from("career").select("role,start_year,end_year,companies(name)").eq("member_id", user.id).order("sort");
      const { data: rk } = await admin.from("review_tokens").select("token").eq("member_id", user.id).maybeSingle();
      const link = (d: string) => `${env("APP_URL")}?review=${user.id}&key=${rk?.token ?? ""}&do=${d}`;
      const li = m.linkedin_url ? (/^https?:/.test(m.linkedin_url) ? m.linkedin_url : "https://" + m.linkedin_url) : "";
      const rows = [["Name", `${m.first_name} ${m.last_name}`], ["Email", c?.email], ["Headline", m.headline],
        ["MBA", s ? `${s.school}, class of ${s.class_year}` : ""], ["Location", m.location], ["Industry", m.industry], ["WhatsApp", c?.phone]]
        .filter(([, v]) => v)
        .map(([k, v]) => `<tr><td style="padding:6px 12px 6px 0;color:#5C6272;vertical-align:top">${k}</td><td style="padding:6px 0">${esc(v)}</td></tr>`).join("");
      const career = (k ?? []).map((x: any) =>
        `<li>${esc(x.role)} · ${esc(x.companies?.name)}${x.start_year ? ` (${x.start_year}–${x.end_year ?? "Present"})` : ""}</li>`).join("");
      const html = `
        <div style="font-family:Arial,sans-serif;font-size:14px;color:#161A26;max-width:560px">
          <h2 style="margin:0 0 4px">New request to join ${NETWORK}</h2>
          <p style="color:#5C6272;margin:0 0 16px">Signed up ${m.signup_source === "linkedin" ? "with their LinkedIn PDF" : "manually"}. Their email is confirmed.</p>
          <table style="border-collapse:collapse;width:100%">${rows}
            ${li ? `<tr><td style="padding:6px 12px 6px 0;color:#5C6272">LinkedIn</td><td style="padding:6px 0"><a href="${esc(li)}">${esc(m.linkedin_url)}</a></td></tr>` : ""}
          </table>
          ${m.join_answer ? `<p style="margin:16px 0 4px;color:#5C6272">Where in Israel are you from, and what did you do before your MBA?</p><p style="margin:0;background:#F7F8F4;padding:10px 12px;border-radius:8px">${esc(m.join_answer)}</p>` : ""}
          ${career ? `<p style="margin:16px 0 4px;color:#5C6272">Career</p><ul style="margin:0;padding-left:18px">${career}</ul>` : ""}
          <p style="margin:24px 0">
            <a href="${esc(link("approve"))}" style="background:#1D7448;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:bold">Approve</a>
            &nbsp;
            <a href="${esc(link("decline"))}" style="background:#F7F8F4;color:#161A26;border:1px solid #E1E3DC;padding:11px 22px;border-radius:10px;text-decoration:none;font-weight:bold">Decline</a>
          </p>
          <p style="color:#8C91A0;font-size:12px">Each button opens a page where you confirm. Approving makes them an official member and sends their welcome email. Admins can also decide in the app under My Network → Admin: join requests.</p>
        </div>`;
      const to = env("ADMIN_EMAILS").split(",").map((x) => x.trim()).filter(Boolean);
      try {
        await send(to, `Join request: ${m.first_name} ${m.last_name}${s ? ` (${s.school} '${String(s.class_year).slice(-2)})` : ""}`, html, c?.email);
      } catch (e) { // un-mark so the next call can retry
        await admin.from("members").update({ admin_notified_at: null }).eq("id", user.id);
        throw e;
      }
      // Tell the applicant their request arrived and is waiting for an admin (best effort).
      try {
        await send([c!.email], `We got your request to join ${NETWORK}`, `
          <div style="font-family:Arial,sans-serif;font-size:15px;line-height:1.5;color:#161A26;max-width:560px">
            <h2 style="margin:0 0 12px">Thanks, ${esc(m.first_name)}. Your request is waiting for approval.</h2>
            <p>An admin reviews every request by hand to keep the network Israeli MBAs only. Most requests are reviewed within a day.</p>
            <p>We'll email you as soon as you're approved. Until then, logging in to <a href="${esc(env("APP_URL"))}">${NETWORK}</a> shows that your request is waiting.</p>
            <p>The ${NETWORK} team</p>
          </div>`);
      } catch (e) { console.error(e); }
      return json({ ok: true, sent: true });
    }

    if (body.action === "welcome" && body.member) {
      const { data: isAdmin } = await admin.from("admins").select("user_id").eq("user_id", user.id).maybeSingle();
      if (!isAdmin) return json({ ok: false, error: "not-admin" }, 403);
      const sent = await sendWelcome(admin, body.member);
      return json({ ok: true, sent });
    }
    if ((body.action === "intro" || body.action === "intro-accepted") && body.intro) {
      const accepted = body.action === "intro-accepted";
      // Only the requester (new intro) or the recipient (accepted) may trigger these, and each goes out once.
      const stamp = accepted ? "accepted_notified_at" : "notified_at";
      const { data: r } = await admin.from("intro_requests")
        .update({ [stamp]: new Date().toISOString() })
        .eq("id", body.intro).eq(accepted ? "recipient_id" : "requester_id", user.id)
        .eq("status", accepted ? "accepted" : "pending").is(stamp, null)
        .select("requester_id,recipient_id,note").maybeSingle();
      if (!r) return json({ ok: true, sent: false });
      const person = async (id: string) => {
        const [{ data: m }, { data: c }, { data: s }] = await Promise.all([
          admin.from("members").select("first_name,last_name,headline,contact_pref").eq("id", id).single(),
          admin.from("member_contacts").select("email,phone").eq("member_id", id).single(),
          admin.from("member_schools").select("school,class_year").eq("member_id", id).order("sort").limit(1).maybeSingle(),
        ]);
        return { ...m, ...c, tag: s ? `${s.school} '${String(s.class_year).slice(-2)}` : "" } as Record<string, string>;
      };
      const [from, to] = await Promise.all([person(r.requester_id), person(r.recipient_id)]);
      const app = esc(env("APP_URL"));
      const button = (label: string) =>
        `<p style="margin:24px 0"><a href="${app}" style="background:#2E49C2;color:#fff;padding:12px 20px;border-radius:10px;text-decoration:none;font-weight:bold">${label}</a></p>`;
      try {
        if (!accepted) {
          await send([to.email], `${from.first_name} ${from.last_name}${from.tag ? ` (${from.tag})` : ""} would like an intro`, `
            <div style="font-family:Arial,sans-serif;font-size:15px;line-height:1.5;color:#161A26;max-width:560px">
              <p>Hi ${esc(to.first_name)},</p>
              <p><b>${esc(from.first_name)} ${esc(from.last_name)}</b>${from.tag ? `, ${esc(from.tag)}` : ""} (${esc(from.headline)}) found you on ${NETWORK} and wrote:</p>
              <p style="margin:0;background:#F7F8F4;padding:12px 14px;border-left:3px solid #2E49C2;border-radius:6px;white-space:pre-wrap">${esc(r.note)}</p>
              ${button("Accept or decline")}
              <p style="color:#5C6272;font-size:13px">If you accept, ${esc(from.first_name)} can reach you on your ${to.contact_pref === "whatsapp" ? "WhatsApp" : "email"}. If you decline, they see a polite note and none of your details. Log in, then go to My Network → Intro requests.</p>
            </div>`);
        } else {
          const how = to.contact_pref === "whatsapp" && to.phone ? `WhatsApp: <b>${esc(to.phone)}</b>` : `email: <b>${esc(to.email)}</b>`;
          await send([from.email], `${to.first_name} accepted your intro`, `
            <div style="font-family:Arial,sans-serif;font-size:15px;line-height:1.5;color:#161A26;max-width:560px">
              <p>Hi ${esc(from.first_name)},</p>
              <p>Good news: <b>${esc(to.first_name)} ${esc(to.last_name)}</b>${to.tag ? ` (${esc(to.tag)})` : ""} accepted your intro. Reach out on their preferred channel, ${how}.</p>
              ${button("Open their profile")}
            </div>`);
        }
      } catch (e) { // un-mark so the next call can retry
        await admin.from("intro_requests").update({ [stamp]: null }).eq("id", body.intro);
        throw e;
      }
      return json({ ok: true, sent: true });
    }
    return json({ ok: false, error: "unknown-action" }, 400);
  } catch (e) {
    console.error(e);
    return json({ ok: false, error: "send-failed" }, 500);
  }
});
