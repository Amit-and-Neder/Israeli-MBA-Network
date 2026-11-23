# Israeli MBA Network

A directory and warm-intro platform for Israeli MBA students and alumni: search by school, class year, company or industry, view profiles with career timelines, star the people you want to keep track of, and request intros over WhatsApp or email.

The app is one page, `index.html`, with no build step. The backend is Supabase (see [`supabase/README.md`](supabase/README.md)).

**What's live so far:** sign-up (with email confirmation), admin approval, login on any device, and the emails for each. Search, profiles, company pages and intros still run on the built-in sample members until the next phases connect them to the database.

**Demo mode:** with `SUPABASE_URL` empty at the top of the backend section in `index.html`, the whole app runs on sample data and sends nothing.

## Run it

Open `index.html` in any browser, or serve the folder:

```bash
python3 -m http.server 8000
```

then visit http://localhost:8000.
