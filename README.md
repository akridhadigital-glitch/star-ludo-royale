# Star Ludo Royale

Classic Ludo for Android and iOS, with smooth animations, smart bots, Pass & Play, and online private rooms.

| | |
|---|---|
| **App** | Flutter (`app/`): splash, home, vs Computer, Pass & Play, online rooms, leaderboard, profile, legal |
| **Server** | Node.js + TypeScript (`server/`): Fastify REST, Socket.IO real-time, PostgreSQL, Redis |
| **Rules** | One engine in TypeScript and an identical Dart port, both tested against `shared/fixtures/engine-fixtures.json` |

## Features

- **Ludo King–style rules:** a 6 to leave the yard, a bonus roll for a 6, a capture or reaching home, three 6s in a row forfeits the turn, 8 safe stars, and an exact roll to finish.
- **vs Computer:** 2 to 4 players, pick your colour; bots prefer captures and safety and avoid danger.
- **Pass & Play:** 2 to 4 people on one phone, no bots.
- **Online private rooms:** 6-character codes for 2 to 4 players; the host starts the match.
  - The **server is the referee**: it rolls the dice with a crypto RNG and checks every move. Clients only send "roll" or "move token N".
  - **15-second turn timer:** the server auto-plays for idle or disconnected players.
  - **Rejoin after a network drop**, even after a server restart (room state lives in Redis).
  - **Leaving counts as a loss.** If everyone else leaves, the last player wins.
  - **Quick chat** with fixed phrases only, so there's nothing to moderate.
- **Accounts:** instant guest login (random device ID), optional **Google link** (Firebase Auth) to keep progress across phones, and **delete account** (DPDP right to erasure).
- **Leaderboard** by online wins. Coins and gems are rewards only and **can never be bought or cashed out** (see *Legal* below).
- **Feel:** tokens glide and hop square by square, the dice tumbles, captured tokens fly home, plus sounds, haptics, turn rings, an animated splash logo, and saved offline matches you can continue.

## Repository layout

```
app/        Flutter app
  lib/engine/      rules engine (Dart port)
  lib/game/        board painter, pieces, match controllers, game screen
  lib/screens/     splash, home, online lobby, leaderboard, profile, legal
  lib/core/        API client, socket service, session, storage, sound
server/     Node.js server
  src/engine/      rules engine (source of truth)
  src/rooms/       room manager (referee, timers, rejoin) + Redis store
  src/http.ts      REST API     src/socket.ts  Socket.IO protocol
  test/            engine tests + end-to-end tests (real Postgres + Redis + sockets)
shared/fixtures/   recorded games both engines must reproduce exactly
docs/              protocol, deployment, legal pages
```

## Run the server

**Free hosting (no expiry):** Render free web service + Neon free Postgres; see [docs/DEPLOY.md](docs/DEPLOY.md). Redis is optional (`REDIS_URL`); without it, live rooms are kept in memory.

**Docker (easiest):**

```bash
cp server/.env.example server/.env      # set JWT_SECRET: openssl rand -hex 32
docker compose up -d --build
curl localhost:8080/health              # {"ok":true}
```

**Without Docker:** you need Node 20+, Postgres 14+ and Redis 6+.

```bash
cd server
cp .env.example .env    # edit DATABASE_URL / REDIS_URL / JWT_SECRET
npm install
npm run dev             # migrations run automatically on start
```

**Tests:**

```bash
cd server
npm test   # engine tests only

# with a test Postgres and Redis, also the end-to-end tests:
TEST_DATABASE_URL=postgres://... TEST_REDIS_URL=redis://... npm test
```

## Run the app

Requires Flutter 3.27 or newer.

```bash
cd app
# First time only: generate the android/ and ios/ folders (does not touch lib/)
flutter create . --project-name star_ludo_royale --org com.starludoroyale --platforms android,ios
rm -f test/widget_test.dart

flutter pub get
flutter test
flutter run                                              # emulator → server on your PC (10.0.2.2:8080)
flutter run --dart-define=API_URL=http://192.168.1.5:8080  # real phone on the same Wi-Fi
flutter build apk --release --dart-define=API_URL=https://api.yourdomain.com
```

Offline modes work with no server at all.

### Google sign-in (optional)

Guest login works without it. To enable "Link Google account":

1. Create a Firebase project. Under **Authentication → Sign-in method**, enable **Google**.
2. Add an Android app with your package name (`com.starludoroyale.star_ludo_royale` unless you changed it) and your SHA-1 (`cd android && ./gradlew signingReport`).
3. Download `google-services.json` into `app/android/app/`. For iOS, add `GoogleService-Info.plist` to `ios/Runner/`.
4. Apply the Google services Gradle plugin (see the [FlutterFire docs](https://firebase.google.com/docs/flutter/setup)). Running `flutterfire configure` does this for you.
5. On the server, set `FIREBASE_PROJECT_ID=<your project id>`.

## CI

`.github/workflows/ci.yml` runs on every push:

- **Server:** typecheck, engine tests, end-to-end tests against Postgres and Redis, build, and a Docker image build.
- **App:** `flutter analyze`, `flutter test` (including the cross-engine fixture test), and a release APK, which you can download from the run's **Artifacts**.

Set the repository variable `API_URL` (Settings → Secrets and variables → Actions → Variables) so the CI-built APK points at your server.

## Changing the rules

1. Edit `server/src/engine/engine.ts` **and** `app/lib/engine/engine.dart` the same way.
2. Regenerate the fixtures: `cd server && npm run fixtures`.
3. Run both test suites. CI fails if the two engines disagree on any move.

## Legal (India)

- The game is a free **online social game**: no entry fees, no stakes, no prizes, and virtual coins and gems that cannot be bought or redeemed. Under the Promotion and Regulation of Online Gaming Act, 2025, games with money stakes are banned; social games are allowed. **Do not add paid coins, entry fees or cash prizes.** For income, use ads, a paid "remove ads", or cosmetic items that can't be staked or traded, and get legal advice first.
- Privacy Policy and Terms are in the app (`app/lib/screens/legal_screen.dart`) and in `docs/legal/` for hosting on a website (the Play Store needs a public privacy-policy URL).
- **Before launch:**
  - Fill in the operator name, email and city in `legal_screen.dart` and `docs/legal/*.md`.
  - Check the name "Star Ludo Royale" on the Indian trademark registry.
  - Have a lawyer review once.

See [docs/DEPLOY.md](docs/DEPLOY.md) for production deployment and [docs/PROTOCOL.md](docs/PROTOCOL.md) for the API.
