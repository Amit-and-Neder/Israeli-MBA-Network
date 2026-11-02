# Working together

Amit (`AmitG1995`) and Neder (`neder-nesel`) both work on this repo. To keep our work separate, every change goes through its own branch and a pull request.

## The rules

- **`main` is the finished, shared version.** Nobody pushes to it directly. GitHub blocks it.
- **One branch per feature,** named `feature/<short-name>`, e.g. `feature/search-filters` or `feature/dark-mode`.
- **Merging into `main` takes a pull request approved by the other partner.** Amit reviews Neder's PRs and Neder reviews Amit's.
- If you push new commits after an approval, the approval resets and the PR needs another review.

## Step by step

1. Start from the latest `main`:
   ```bash
   git checkout main
   git pull
   ```
2. Create your feature branch:
   ```bash
   git checkout -b feature/search-filters
   ```
3. Make changes, then commit and push them. Repeat as often as you like:
   ```bash
   git add .
   git commit -m "Add industry filter to search"
   git push -u origin feature/search-filters
   ```
4. Open a pull request on GitHub (or run `gh pr create`), and ask your partner to review it.
5. Your partner reviews the changes, comments if needed, and clicks **Approve**.
6. Merge the PR on GitHub, then delete the branch.

## Tips

- Keep each branch to one feature. Smaller PRs are quicker to review.
- If you're both changing the same part of `index.html`, tell each other first to avoid conflicts.
- To test the app, open `index.html` in a browser.
