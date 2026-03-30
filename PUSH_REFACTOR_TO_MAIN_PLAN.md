# Plan: Backup Old Main, Then Make Main = Refactor

**Goal:** Keep current `main` (old code) as a backup on GitHub, then make `main` the refactored code.

---

## Step 1 — Commit any pending work on the refactor branch

You have uncommitted changes on `v2-frontend-refactor` (CORS fix, login error message, version label, audit summary). Commit them so the refactor branch is complete before merging.

```powershell
cd c:\src\GymSaaS
git checkout v2-frontend-refactor
git add backend/app/main.py frontend/lib/main.dart frontend/lib/screens/login_screen.dart REFACTOR_AUDIT_SUMMARY.md
# Optional: add generated plugin files if you want them in history:
# git add frontend/linux/flutter/generated_plugin_registrant.cc frontend/linux/flutter/generated_plugins.cmake frontend/macos/Flutter/GeneratedPluginRegistrant.swift frontend/windows/flutter/generated_plugin_registrant.cc frontend/windows/flutter/generated_plugins.cmake
git commit -m "CORS localhost regex, login error hint, version label, refactor audit summary"
```

---

## Step 2 — Create a backup branch from current main (old code) and push it

This saves the pre-refactor state on GitHub under a named branch with `_old` so you can clearly see it's the old code.

```powershell
git checkout main
git pull origin main
git branch main_old
git push origin main_old
```

You can use another name if you prefer, e.g. `main_pre_refactor_old`.

---

## Step 3 — Make main = refactor and push

Merge the refactor into `main`, then push.

```powershell
git checkout main
git merge v2-frontend-refactor -m "Merge refactor: modular backend (app/), typed frontend models, web-safe client"
git push origin main
```

If you hit merge conflicts, resolve them, then `git add` and `git commit` and push again.

---

## Step 4 — Verify on GitHub

- **main** — refactored code (modular backend, typed frontend).
- **main_old** — snapshot of the old main; name has `_old` so you know it's the pre-refactor code. Keep as long as you want.

---

## Summary

| Branch | Purpose |
|--------|---------|
| `main` | Production: refactored code (after Step 3). |
| `main_old` | Backup of old main (`_old` = pre-refactor); safe to keep forever or delete later. |
| `v2-frontend-refactor` | Can keep for history or delete after merge. |

You can always restore the old code with:  
`git checkout main_old`
