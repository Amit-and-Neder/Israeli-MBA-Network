# Backend: Supabase

The app's backend is a Supabase project: a Postgres database, logins, and one small email function.
It replaced an earlier Google Sheet + Apps Script backend, which has been removed from the repo.

## What's here

| File | What it does |
|---|---|
| `migrations/20261116000000_init.sql` | Members, sign-up, admin approval: tables, privacy rules and functions. Run once. |
| `migrations/20261201000000_reports.sql` | Members report a profile to the admins (`report_member`); admins review and resolve (`admin_reports`, `admin_resolve_report`). No blocking. Run once, after the status-note file. |
| `migrations/20261202000000_name_validation.sql` | First and last names: letters (English, accented, Hebrew, Arabic, Cyrillic), spaces, hyphens, apostrophes and periods only. No digits, SQL symbols or `--`. Run once, after the reports file. |
| `migrations/20261203000000_security_hardening.sql` | Members read only other members' public columns; size limits on every text field and list (40 jobs, 5 schools); the sign-up "email taken?" check is limited to 20 an hour per visitor. Run once, after the reports file. |
| `migrations/20261204000000_name_check_service_role.sql` | Fix: lets the email function (service_role) write to members again. The name rule's check function was locked too tightly, which blocked admin "new request" emails, the emailed Approve/Decline buttons and welcome emails. Run once, after the security file. |
| `migrations/20261205000000_linkedin_verification.sql` | New members verify with "Sign in with LinkedIn"; the submitted name must match the LinkedIn account (`linkedin-name-mismatch`), and admins see "Verified via LinkedIn". Switch: `app_settings.require_linkedin`. Run only after LinkedIn is on in Supabase and the site's LinkedIn step is live. |
| `migrations/20261130000000_status_note.sql` | Status notes: a short public "speech bubble" each member writes (`set_my_status`, `status_notes`). Run once, after the contacts-for-members file. |
| `migrations/20261129000000_contacts_for_members.sql` | Every approved member sees the email and WhatsApp each approved member shares, with no intro. Run once, after the contact-sharing file. |
| `migrations/20261128000000_contact_sharing.sql` | Members share email, WhatsApp or both, and pick a preferred one. Emails are read through `visible_contacts()`, which hides unshared ones. Run once, after the email-check file, at the same time the matching site change goes live. |
| `migrations/20261127000000_email_check.sql` | `email_in_use()`: lets the sign-up form say early that an email already has an account (true/false only). Run once, after the email-approval file. |
| `migrations/20261126000000_email_approval.sql` | One-time keys behind the Approve/Decline buttons in the admin email. Run once, after the accounts file. |
| `migrations/20261125000000_accounts.sql` | Lets a member delete their own account. Run once, after the member-data file. |
| `migrations/20261124000000_member_data.sql` | Everything members do after joining: profile edits, photos, stars, Feed posts, "interested" and intros. Run once, after the first file. |
| `functions/notify/index.ts` | Sends the app's emails: new join request (to admins), welcome (on approval), intro request (to the person asked) and intro accepted (to the person who asked). |
| `tests/` | Privacy tests that run on a local Postgres (`tests/run.sh`). 129 checks, e.g. a member can't read another member's phone number or post as someone else. |

## Who can see what

- **Logged out:** nothing.
- **Pending** (signed up, not approved yet): only their own profile.
- **Approved members:** every approved member's profile, schools and career.
- **Phone and email:** only the member themselves, admins, and someone whose intro they accepted. Accepting is one way: the person who asked gets your details, not the other way round.
- **Photos:** private files. Approved members see approved members' photos; pending members see only their own.
- **Stars and "interested":** private to the person who made them. Nobody is told they were starred.
- **Feed:** approved members read every approved member's posts and can post up to 10 times a day. Only the author or an admin can delete a post.
- **Intros:** only approved members, one open request per pair, up to 10 new requests a day. Only the person asked can accept or decline.
- **Admins:** pending requests, including the applicant's email and phone, and the Approve / Decline buttons.

The database enforces all of this itself. The page can't override it, and nobody can approve themselves or edit someone else's profile.

## Sign-up and login

- **The first page is Log in:** email and password, with **Forgot password?** under the fields and the sign-up banner below.
- **Sign up:** the member fills in the form from their LinkedIn PDF and chooses a password. Supabase emails them a 6-digit code ("Confirm sign up" template). The code proves the email is theirs; then the request is saved as "pending" and the admins get an email.
- **Approval:** each new request emails the admins (`ADMIN_EMAILS`, now israeli.network.app@gmail.com) with **Approve** and **Decline** buttons, and emails the applicant that their request is waiting. A button opens a confirmation page on the site; confirming records the decision and, on approval, sends the welcome email. The buttons use a private one-time key per request (`migrations/20261126000000_email_approval.sql`) and stop working once the request is decided. Admins can also decide in the app under **Network → Admin: join requests**.
- **Waiting for approval:** until then, a member who logs in sees only a "Your request is waiting for approval" page (with Check again and Log out). Declined members see a short note.
- **Staying logged in:** the login is saved in the browser and renewed automatically. Sessions have no time limit (Authentication → Sessions), so members stay logged in until they log out or change their password.
- **Forgot password:** Supabase emails a 6-digit code ("Reset password" template); the member enters it with a new password and is logged in. Their other devices are logged out.
- **Account settings** (in the app): change password (checks the current one; other devices are logged out, this one stays in), log out, log out of all devices, delete account (`migrations/20261125000000_accounts.sql`).
- Members who joined before passwords existed use **Forgot password?** once to set one.
- LinkedIn login can be turned on later (step 7).

## One-time setup (about an hour)

### 1. Create the project
1. Go to [supabase.com](https://supabase.com), sign up, and create a project. Pick the US East region. Under Security, turn **off** "Automatically expose new tables" (the migration grants access explicitly). *(Done: organization "Israeli MBA Network", project `israeli-mba-network`, US East.)*
2. Under **Organization → Team**, invite your partner.

### 2. Create the database
**SQL Editor → New query**, paste all of `migrations/20261116000000_init.sql`, then click **Run**. Supabase warns that the query is "destructive" (it contains revoke/delete statements); on a new project that's expected. It should finish with "Success. No rows returned". *(Done on Nov 16, 2026.)*

Then do the same with `migrations/20261124000000_member_data.sql`. It adds the member-data tables, the two private photo buckets (`avatars`, `post-photos`) and their rules. It's safe to run again if something goes wrong halfway.

### 3. Set up email sending (required)
Supabase's built-in email only delivers to your own Supabase team, so real members would never get their codes.
1. Sign up at [resend.com](https://resend.com) and add a domain you own (**Domains → Add domain**). Then add the DNS records it shows at your domain registrar. Wait until the domain shows "Verified".
2. In Resend, create an API key (**API Keys → Create**).
3. In Supabase, go to **Authentication → Emails → SMTP Settings** and turn on **Enable custom SMTP**:
   - Sender email: e.g. `hello@your-domain.com`. Sender name: `Israeli MBA Network`
   - Host `smtp.resend.com`, port `465`, username `resend`, password: the Resend API key

#### Until there's a domain: send from a Gmail account
Gmail works for both kinds of email, at up to about 500 a day. Messages come from the Gmail address and are more likely to land in spam than with Resend.
1. On that Google account, turn on **2-Step Verification**, then create an **app password** at [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords). Google shows 16 letters. Keep them private: they let anyone send mail as you.
2. **Login codes:** in **Authentication → Emails → SMTP Settings**, turn on custom SMTP with host `smtp.gmail.com`, port `465`, username = the Gmail address, password = the app password, sender email = the same Gmail address, sender name `Israeli MBA Network`.
3. **The app's other emails:** in **Edge Functions → Secrets**, set `SMTP_HOST` = `smtp.gmail.com`, `SMTP_PORT` = `465`, `SMTP_USER` = the Gmail address, `SMTP_PASSWORD` = the app password, and `FROM_EMAIL` = `Israeli MBA Network <the Gmail address>`. Skip `RESEND_API_KEY`.

Switching to Resend later: replace the SMTP settings in step 2 with Resend's, delete the `SMTP_*` secrets and add `RESEND_API_KEY`.

### 4. Make the emails show a code
Under **Authentication → Sign In / Providers → Email**, set **Minimum password length** to 8 and **Email OTP length** to 6.
Under **Authentication → Emails → Templates**, edit **Confirm sign up**, **Reset password** and **Magic link** so the body shows the code instead of a link. For example:
```html
<h2>Your Israeli MBA Network code</h2>
<p>Enter this code to continue: <b style="font-size:22px;letter-spacing:3px">{{ .Token }}</b></p>
<p>If you didn't ask for it, you can ignore this email.</p>
```

### 5. Deploy the email function
**Edge Functions → Deploy a new function → Via Editor**. Name it `notify`, paste `functions/notify/index.ts`, and click **Deploy**. After any change to that file, open the function, paste the new version and deploy again.
Then, under **Edge Functions → Secrets**, add:

| Name | Value |
|---|---|
| `RESEND_API_KEY` | the Resend API key |
| `FROM_EMAIL` | `Israeli MBA Network <hello@your-domain.com>` |
| `ADMIN_EMAILS` | who gets new-request emails, comma-separated |
| `APP_URL` | the site's address, e.g. `https://neder-nesel.github.io/israeli-mba-network/` |

### 6. Connect the app and add admins
1. Copy the **Project URL** (project home page) and the **Publishable key** (**Settings → API Keys**) into the top of the backend section in `index.html` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`). Both are public by design. **Never** put a secret key (or the legacy `service_role` key) in the page or in GitHub. *(Already done for project `ipslqfrtebxtugcoechb`.)*
2. **Authentication → URL Configuration**: set **Site URL** to the site's address, and add it under **Redirect URLs**. Add `http://localhost:8000` too, for testing.
3. Sign up through the app yourself. Then, in **Table Editor → admins**, add a row with your user id (find it under **Authentication → Users**). In **Table Editor → members**, set your own `status` to `approved`. After that, approve everyone else from the app.

### 7. Optional: LinkedIn login
1. At [linkedin.com/developers/apps](https://www.linkedin.com/developers/apps), create an app and request **Sign In with LinkedIn using OpenID Connect**.
2. Under the LinkedIn app's **Auth** tab, add the redirect URL `https://<your-project>.supabase.co/auth/v1/callback`.
3. In Supabase, go to **Authentication → Sign In / Providers → LinkedIn (OIDC)**. Turn it on and paste the LinkedIn Client ID and Client Secret.
4. In `index.html`, set `LINKEDIN_LOGIN=true`.

## Free plan vs. Pro
The free plan is enough to build and test. But free projects pause after a week with no activity, so the site would go offline until someone restores it from the dashboard. Upgrade to Pro before inviting real members.

## Running the privacy tests
They need a local Postgres 15 or newer. They create and drop a throwaway database called `imn_privacy_test`.
```bash
PGHOST=localhost PGUSER=postgres supabase/tests/run.sh
```
Run them after any change to the migration. Every line should say PASS.

## Changing the database later
Don't edit the migration that's already been run. Add a new file in `migrations/` (e.g. `20261201000000_profiles.sql`), run it in the SQL Editor, and add tests for anything it changes about who can see what.
