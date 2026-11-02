# Sign-up backend (Google Sheet + Gmail)

`Code.gs` is a small Google Apps Script that handles real sign-ups:

1. A new member submits the sign-up form. Their request is saved as a row in a Google Sheet.
2. The admin gets an email with the applicant's details and a **Review and approve** button.
3. The button opens a page where the admin clicks **Approve** or **Decline**. Approving marks the member approved in the Sheet and sends them the official welcome email.
4. The next time the member opens the app, it sees they've been approved.

Emails are sent from the Google account that sets this up. Free Gmail accounts can send about 100 emails a day.

## One-time setup (about 10 minutes)

1. **Create the Sheet.** Go to [sheets.new](https://sheets.new) while signed in to the admin's Google account, and name it "Israeli MBA Network – Sign-ups".
2. **Add the script.** In the Sheet, open **Extensions → Apps Script**. Delete the sample code, paste in all of `Code.gs` from this folder, and click **Save**.
3. **Set the admin email (optional).** Approval emails go to the Google account that runs the script. To send them somewhere else, open **Project Settings** (gear icon) → **Script properties** → **Add script property**, with the name `ADMIN_EMAIL` and your email as the value.
4. **Deploy it.** Click **Deploy → New deployment**. Under the gear next to "Select type", choose **Web app**, then set:
   - **Execute as:** Me
   - **Who has access:** Anyone

   Click **Deploy**, then **Authorize access**. Google asks for permission to manage the Sheet and send email as you. If it says "Google hasn't verified this app", click **Advanced → Go to (project name)**. That's expected for your own script.
5. **Copy the Web app URL.** It ends in `/exec`.
6. **Connect the app.** In `index.html`, find `const BACKEND_URL='';` and paste the URL between the quotes. Commit that change on a feature branch, like any other.

## Updating the script

After editing `Code.gs`, paste it into Apps Script again, then click **Deploy → Manage deployments → Edit (pencil) → Version: New version → Deploy**. This keeps the same URL.

## Notes

- **The Sheet is your member list.** Its `status` column says `pending`, `approved` or `declined`. Don't rename the columns.
- **Approve links are secret.** Each email has its own private link. Don't forward approval emails.
- **The web app URL is public** once it's in `index.html`, so anyone could submit a request. That's fine, since nobody gets in without the admin approving.
- **Declining doesn't email the applicant.**
