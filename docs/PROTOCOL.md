# API & real-time protocol

## REST (`/v1`)

| Method | Path | Auth | Body | Returns |
|---|---|---|---|---|
| GET | `/health` | none | none | `{ ok: true }` |
| POST | `/v1/auth/guest` | none | `{ deviceId (16–128 chars, [A-Za-z0-9_-]), name? }` | `{ token, user }` (same device → same user) |
| POST | `/v1/auth/google` | optional guest token | `{ idToken }` (Firebase ID token) | `{ token, user, linked }`, see below |
| GET | `/v1/me` | Bearer | none | `{ user, activeRoom }` (`activeRoom` = room to rejoin, or null) |
| PATCH | `/v1/me` | Bearer | `{ name?, avatar? (0–11) }` | `{ user }` |
| DELETE | `/v1/me` | Bearer | none | 204, deletes the account and stats |
| GET | `/v1/leaderboard` | none | none | `{ players: [{ rank, name, avatar, wins, gamesPlayed }] }` (top 50) |

How `/v1/auth/google` decides which account to use:

- If that Google account is already linked to a player, it logs into that player.
- Otherwise, if a guest token is sent, it links Google to that guest, so progress is kept.
- Otherwise, it creates a new player.

`user` = `{ id, name, avatar, coins, gems, gamesPlayed, wins, captures, hasGoogle }`.

Errors: `{ error: "<code>" }` with HTTP 400/401/429/501/500.

## Socket.IO

Connect with `auth: { token }`. Every client→server event takes `(payload, ack)`; the ack gets `{ ok: true, ... }` or `{ ok: false, error }`.

| Event | Payload | Notes |
|---|---|---|
| `room:create` | `{ maxPlayers: 2\|3\|4 }` | → `{ room }`; the creator is host |
| `room:join` | `{ code }` | → `{ room }`. Errors: `room_not_found`, `room_full`, `game_already_started`, `already_in_room` |
| `room:resume` | `{}` | → `{ room \| null }`; re-attaches after reconnect or app restart |
| `room:start` | `{}` | host only, needs ≥ 2 players. Seats: 2 players → red vs yellow; 3 → red/green/yellow; 4 → all |
| `room:leave` | `{}` | lobby: leave the room; in game: forfeit |
| `game:roll` | `{}` | `not_your_turn`, `not_roll_phase` |
| `game:move` | `{ token: 0–3 }` | `illegal_move`, `not_move_phase` |
| `chat:send` | `{ id }` | ids: `gg luck hurry nice oops six wow laugh angry cool fire crown` (1 per 1.5 s) |

Server → client:

- `room:update`: the full `RoomView`. Fields: `code`, `hostId`, `maxPlayers`, `status` (`lobby | playing | finished`), `members[]`, `game`, `deadline`, `result`.
  - Each member: `{ userId, name, avatar, color, connected, left, away }`.
  - `game` is the engine `GameState`.
  - `deadline` is the epoch ms when the current turn auto-plays.
  - `result` is `{ ranking[], rewards{userId:{coins,gems}}, reason }`.
- `game:events`: `{ events[], game, deadline, actor, auto }`. Clients animate `events` in order, then adopt `game`. `game.moveNo` increases by one per action; ignore anything at or below the last one you applied.
- `chat:message`: `{ userId, id }`.

Event types (shared with the Dart engine): `rolled`, `three_sixes`, `no_move`, `moved {token, from, to}`, `captured {victims[]}`, `home`, `bonus {reason: six|capture|home}`, `turn`, `over {winner, ranking}`.

## Timers

- **Connected player:** `TURN_SECONDS` (default 15) to act, then the server auto-plays.
- **Disconnected player, or after 2 missed turns:** auto-played after 2.5 s until they act again.
- **Finished rooms:** deleted after 10 minutes. Room snapshots expire from Redis after 6 hours.
