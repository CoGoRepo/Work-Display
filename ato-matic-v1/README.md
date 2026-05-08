# ATO-Matic v1

1. Copy `.env.example` to `.env`.
2. Edit `.env` and set real values for `DB_PASSWORD` and `SESSION_SECRET`.
3. Set `ATO_MATIC_IMAGE` to the published image tag you were given.
4. Run:

```powershell
docker compose up -d
```

Open http://localhost:8000 and sign in with:

- Email: Dadmin@ato-matic.com
- Password: TemPWD2026!!

The database is initialized from `init/dump.sql` the first time the Postgres volume is created.
