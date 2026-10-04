# IMPORTANT: keep private data out of this repository

This repository is **public**. You can run your own deployment from it, but nothing personal may ever be committed: no keys, passwords, server addresses, phone numbers or call data.

## Where your private values live

All of these are git-ignored. Keep them that way.

| File or folder | What it holds |
|---|---|
| `.env` | Apple team ID, server address (`LOOKUP_URL`), Fly app name (`FLY_APP`), server token, dashboard password |
| `private/` | Call-history copies, notes, screenshots, and `guard-patterns.txt` (your personal patterns) |
| `server/fly.toml` | Your Fly app. Start it from `server/fly.example.toml` |
| `Shared/LookupSecrets.swift`, `Lookup/Info.plist` | Generated from `.env` by `python3 scripts/create_project.py` |
| `build/` | Build output, including signing profiles |

In tracked files, refer to your server as `<your-app>`, never by its real name.

## Install the privacy guard in every clone

```sh
scripts/privacy_guard.sh --install
```

This adds pre-commit and pre-push hooks. They block any commit or push that adds:

- a value from `.env`
- a pattern from `private/guard-patterns.txt`, one regular expression per line, such as your computer's name, device IDs, phone numbers or email address
- a file that must never be committed: `.env` files, anything in `private/`, call-history copies, signing profiles, generated secrets, `server/fly.toml` or `Lookup/Info.plist`

The guard never prints the value it found. Hooks live in `.git/hooks` and are not pushed, so a fresh clone needs the install command again.

## Two things to know

- The guard only protects this clone. Hooks aren't pushed, so a new clone needs `scripts/privacy_guard.sh --install` once. The README now says so.
- It can be bypassed on purpose with `git commit --no-verify`. The push check catches those commits unless the push is also forced past the guard.

## Rules

1. **Never bypass the guard.** Don't use `git commit --no-verify` or `git push --no-verify`. If the guard blocks something, remove the private data rather than forcing it through.
2. **Commit before you deploy,** so the running server always matches a commit in the repository.
3. **Keep secrets out of docs and chat logs.** Don't paste tokens, passwords or real phone numbers into README files, issues or commit messages. Use placeholders.
4. **Data uploaded to your server stays behind its password.** The dashboard's list of blocked numbers lives on your server, never in the repository.
5. **Older commits are not rewritten.** Some contain details from before the guard existed. Everything added since is checked.

## For AI coding agents working in this repository

Follow the rules above. Before every commit, make sure the guard is installed, then let it run. Never add `.env` values, the contents of `private/`, or real phone numbers to tracked files. Never print secrets in your output.
