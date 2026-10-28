# Deploying to production

## Server

### Free forever: Render + Neon

1. **Neon:** go to https://neon.tech and sign up (no card needed). Create a project, region **Singapore**, then copy the **connection string** (`postgresql://...neon.tech/neondb?sslmode=require`).
2. **Render:** choose New → Blueprint, pick this repo, paste the Neon string into `DATABASE_URL`, then click Apply.
3. When the service shows **Live**, set the repo variable `API_URL` to its `https://...onrender.com` address and re-run CI. The website and APK are rebuilt to use it.

Free limits:

- **Server:** sleeps after 15 minutes idle; the first request takes about 1 minute to wake it.
- **Monthly hours:** 750 free instance hours a month, enough for one always-used server.
- **Neon:** 1 GB storage and 100 compute-hours a month per project.
- **Live rooms:** with no Redis, a server restart ends rooms that are in progress. Accounts, coins and the leaderboard are safe in Postgres.

### Other options

Any host that runs Docker works: Railway, Render, Fly.io, or a VPS (DigitalOcean or Hetzner, about ₹500–1,000 a month to start).

**Single VPS:**

```bash
git clone <repo> && cd star-ludo-royale
cp server/.env.example server/.env
# edit server/.env:
#   JWT_SECRET=$(openssl rand -hex 32)
#   CORS_ORIGIN=https://yourdomain.com
#   FIREBASE_PROJECT_ID=...   (only if using Google sign-in)
POSTGRES_PASSWORD=$(openssl rand -hex 16) docker compose up -d --build
```

Put **HTTPS** in front of it. The app needs `https://` and `wss://` in production, and the Privacy Policy promises encrypted connections. Caddy is the simplest option:

```
api.yourdomain.com {
  reverse_proxy localhost:8080
}
```

**Managed services:** point `DATABASE_URL` and `REDIS_URL` at managed Postgres and Redis, and run the `server/` Docker image. Migrations run on start.

### Checklist

- [ ] HTTPS enabled; app built with `--dart-define=API_URL=https://api.yourdomain.com`
- [ ] Strong `JWT_SECRET` (changing it logs everyone out)
- [ ] Daily Postgres backups
- [ ] Redis persistence (`appendonly yes`, already set in docker-compose)
- [ ] `/health` monitored (e.g. UptimeRobot)

### Scaling past one server

Rooms run in the memory of the server process, with their state saved in Redis. One server handles thousands of concurrent matches. To run several:

- Add `@socket.io/redis-adapter`.
- Turn on **sticky sessions** at the load balancer.
- Route each room to one instance, for example by hashing the room code.

## App stores

**Android:**

- Create an upload keystore, configure `android/app/build.gradle` signing, then run `flutter build appbundle --release --dart-define=API_URL=...`.
- Play Console needs:
  - a privacy-policy URL (host `docs/legal/privacy-policy.md`, e.g. on GitHub Pages or your website)
  - the Data safety form: device ID, name and game stats collected; no data shared or sold; encrypted in transit; users can request deletion
  - a content rating (IARC); simulated gambling: **No**

**iOS:**

- You need an Apple Developer account.
- Set the bundle id and team in Xcode, then run `flutter build ipa`.
