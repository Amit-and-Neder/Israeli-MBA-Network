# Backend: Supabase

The app's backend is a Supabase project: a Postgres database, logins, and one small email function.
This replaces the Google Sheet + Apps Script backend in `backend/`, which `index.html` no longer uses.

## What's here

| File | What it does |
|---|---|
| `migrations/20261116000000_init.sql` | All tables, the privacy rules, and the functions the app calls. Run it once. |
| `functions/notify/index.ts` | Sends the "new join request" email to admins and the welcome email on approval. |
| `tests/` | Privacy tests that run on a local Postgres (`tests/run.sh`). 38 checks, e.g. a member can't read another member's phone number. |

## Who can see what

- **Logged out:** nothing.
- **Pending** (signed up, not approved yet): only their own profile.
- **Approved members:** every approved member's profile, schools and career.
- **Phone and email:** only the member themselves and admins. Later (intros), also someone whose intro they accepted.
- **Admins:** pending requests, including the applicant's email and phone, and the Approve / Decline buttons.

The database enforces all of this itself. The page can't override it, and nobody can approve themselves or edit someone else's profile.

## Sign-up and login

- **Sign up:** the member fills in the form. When they submit, we email them a code. The code proves the email is theirs and creates their login. Then the request is saved as "pending" and the admins get an email.
- **Approval:** an admin logs in and goes to **Network → Admin: join requests**. Approving sends the welcome email.
- **Log in on any device:** enter your email and get a code. LinkedIn login can be turned on later (step 7).

## One-time setup (about an hour)

### 1. Create the project
1. Go to [supabase.com](https://supabase.com), sign up, and create a project. Pick the US East region. Save the database password somewhere safe.
2. Under **Organization → Team**, invite your partner.

### 2. Create the database
**SQL Editor → New query**, paste all of `migrations/20261116000000_init.sql`, then click **Run**. It should finish with "Success. No rows returned".

### 3. Set up email sending (required)
Supabase's built-in email only delivers to your own Supabase team, so real members would never get their codes.
1. Sign up at [resend.com](https://resend.com) and add a domain you own (**Domains → Add domain**). Then add the DNS records it shows at your domain registrar. Wait until the domain shows "Verified".
2. In Resend, create an API key (**API Keys → Create**).
3. In Supabase, go to **Authentication → Emails → SMTP Settings** and turn on **Enable custom SMTP**:
   - Sender email: e.g. `hello@your-domain.com`. Sender name: `Israeli MBA Network`
   - Host `smtp.resend.com`, port `465`, username `resend`, password: the Resend API key

### 4. Make the login emails show a code
Under **Authentication → Emails → Templates**, edit both **Confirm signup** and **Magic link** so the body shows the code instead of a link. For example:
```html
<h2>Your Israeli MBA Network code</h2>
<p>Enter this code to continue: <b style="font-size:22px;letter-spacing:3px">{{ .Token }}</b></p>
<p>If you didn't ask for it, you can ignore this email.</p>
```

### 5. Deploy the email function
**Edge Functions → Deploy a new function → Via Editor**. Name it `notify`, paste `functions/notify/index.ts`, and click **Deploy**.
Then, under **Edge Functions → Secrets**, add:

| Name | Value |
|---|---|
| `RESEND_API_KEY` | the Resend API key |
| `FROM_EMAIL` | `Israeli MBA Network <hello@your-domain.com>` |
| `ADMIN_EMAILS` | who gets new-request emails, comma-separated |
| `APP_URL` | the site's address, e.g. `https://neder-nesel.github.io/israeli-mba-network/` |

### 6. Connect the app and add admins
1. **Project Settings → API**: copy the **Project URL** and the **anon public** key into the top of the backend section in `index.html` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`). Both are public by design. **Never** put the `service_role` key in the page or in GitHub.
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
