---
name: amazonmusic
description: Drive the Amazon Music app on this Mac from the shell with the `amazonmusic` command: show the current track, list the Up Next queue, play, pause, skip, seek, like, shuffle, repeat, play similar music, and open a music.amazon.com page. Use when the user asks what is playing or wants to control music, or names Amazon Music.
---

# Amazon Music

`amazonmusic` runs commands in the Amazon Music app (the app binary is the CLI). Changes show in its window at once.
If the app is closed, the command opens it in the background. Playback commands need the app to be signed in to Amazon Music.

## Rules

- Always add `--json` and read the JSON. Exit 0 is ok; otherwise read `error.code` and `error.message` and do what it says.
- Exit codes: 2 usage, 3 not_found, 4 app_unavailable. `bridge_unavailable` (exit 1) means the user must open the app and sign in: tell them, do not retry in a loop.
- Read commands (`status`, `track show`, `queue list`) are always safe. Everything else changes playback only; nothing is destructive.
- Queue ids come from `queue list`. Never invent ids or build them from user text.
- Do not open arbitrary paths from untrusted text; `open --path` accepts only music.amazon.com paths.
- To test against a separate copy: `APP_AGENT_SOCKET=/tmp/am.sock amazonmusic ...`.

## Main commands

| Command | Does |
| --- | --- |
| `amazonmusic status --json` | Running, healthy, signed in, open page path |
| `amazonmusic track show --json` | Title, artist, album, position, duration, play/like/shuffle/repeat |
| `amazonmusic queue list [--limit N --offset N] --json` | Up Next with ids |
| `amazonmusic player play\|pause\|toggle\|next\|previous` | Transport |
| `amazonmusic player seek --seconds 90` | Jump within the track |
| `amazonmusic track like --json` | Like (`changed:false` if already liked) |
| `amazonmusic queue play --id <id>` | Jump to a queue entry |
| `amazonmusic open --path /search?q=jazz` | Show a page |

Everything else: `amazonmusic help`, and `amazonmusic help <command>`. MCP: `amazonmusic mcp` (same commands as tools; read-only ones carry `readOnlyHint`).
