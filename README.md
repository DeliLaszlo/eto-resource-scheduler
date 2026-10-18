# ETO FC Heti Program: operations runbook

Magyarul: [README.hu.md](README.hu.md).

ETO FC Heti Program is the weekly schedule and resource management web app of the football club ETO FC: trainings, matches, pitches, rooms, the dormitory and the weekly program. This is its installation kit, everything a server needs to run it. It contains no source code: the app ships as container images on GitHub Container Registry (`ghcr.io/delilaszlo/eto-backend`, `eto-frontend` and `eto-backup`).

The public repository [eto-resource-scheduler](https://github.com/delilaszlo/eto-resource-scheduler) is published automatically from the private source repository, so changes made there directly get overwritten. Each version tag (`v1.0.0`) matches the image version of the same number. License: MIT, see [LICENSE](LICENSE).

| File | Purpose |
| --- | --- |
| `docker-compose.yaml` | The four services: database, backend, nightly backup, web server |
| `setup.sh` | Writes `.env` once: asks for the outside values and generates every secret |
| `update.sh` | Moves to a new version: backup, restart, health check |
| `proxy/` | HTTPS proxy examples for Caddy and nginx |

## 1. Requirements

**Server**
- Linux on x86-64, 2 vCPU, 4 GB RAM, 20 GB free disk.
- Docker Engine with Compose v2 (`docker compose version` works). Compose 2.33 and 5.6 are tested.
- The clock must be synchronized, because two-step login codes are time-based. Check that `timedatectl` shows `System clock synchronized: yes`.

Measured on a 2 vCPU, 4 GB server: 40 simultaneous users kept the load average under 1 and the whole server under 800 MB of memory, with API answers under 120 ms for 95% of requests. The first PDF starts a Chromium that stays in memory, after which the backend uses about 0.5 GB, up to 0.6 GB while rendering. Disk use is mostly images: about 5 GB while two versions are kept (section 5).

**Network**
- Docker creates its internal networks in `172.17.0.0/16` to `172.31.0.0/16` and `192.168.0.0/16`. If the local network uses any of these, set `default-address-pools` in `/etc/docker/daemon.json` before the first start, or the server can lose contact with that part of the network.
- Outbound access, directly (the app does not support an outbound HTTP proxy):
  - the SMTP server and its port;
  - `ghcr.io` and `registry-1.docker.io` (images);
  - `adatbank.mlsz.hu` (match schedules);
  - `login.microsoftonline.com` and `graph.microsoft.com` (only with Outlook).
- Many hosting providers block outgoing ports 587 and 465. Test before choosing the SMTP port:
  ```bash
  nc -vz -w 5 <smtp-host> 587
  ```
  A timeout means the port is blocked. Most mail services also accept another port, such as 2525.

**Mail service**
- The sender address's domain must authorize the service in DNS (SPF, DKIM and DMARC), or the weekly programme lands in spam.
- The service must not rewrite links (click tracking), add tracking images or add an unsubscribe header. A rewritten link looks like phishing to spam filters. A staff member who clicks an unsubscribe link is silently blocked by the service and stops receiving the weekly programme.
- Before going live, send a test to a Gmail and an Outlook.com address. A new sender domain often lands in Junk at Microsoft even when every check passes.

**HTTPS proxy in front**

The app serves plain HTTP on one port of the server. An HTTPS proxy must sit in front of it, and the app needs a hostname of its own (`eto.example.hu`, not `example.hu/eto/`). The proxy must:
- serve HTTPS only and redirect HTTP to HTTPS;
- forward the whole hostname to the app's port;
- allow request bodies up to 10 MB;
- not buffer `text/event-stream` responses (the progress of a week's finalization);
- allow a read timeout of at least 60 seconds;
- set `X-Forwarded-For`.

Working examples are in `proxy/Caddyfile.example` and `proxy/nginx.conf.example`. A `Strict-Transport-Security` header is recommended and is in both.

**Firewall.** A port that Docker publishes bypasses `ufw`. When the proxy runs on the same machine, `setup.sh` binds the app to `127.0.0.1` and nothing else can reach it. When the proxy runs on another machine, the app listens on the network, so restrict its port to the proxy's address in the cloud or network firewall, or in the `DOCKER-USER` iptables chain.

## 2. Install

Copy this folder to the server, for example to `/opt/etofc`, and work in it. From the machine that has the folder (Linux, macOS or Windows PowerShell):
```bash
scp -r deploy <user>@<server>:~/etofc
ssh <user>@<server> "sudo mv ~/etofc /opt/etofc"
```
Or clone the public repository on the server and check out the version to install:
```bash
sudo git clone https://github.com/delilaszlo/eto-resource-scheduler.git /opt/etofc
sudo chown -R $USER: /opt/etofc
cd /opt/etofc && git checkout v1.0.0
```
The commands below assume the user is in the `docker` group. Otherwise put `sudo` before each `docker` and `sh` command.

1. If the images are private, log in once with a GitHub token that has only the `read:packages` scope:
   ```bash
   docker login ghcr.io -u <github-user>
   ```
2. Write the configuration. The argument is the version to install:
   ```bash
   sh setup.sh 1.0.0
   ```
   It asks for:
   - the public address;
   - how many HTTPS proxies stand in front, and whether the nearest one runs on this machine;
   - the SMTP server, port, user and password, and the sender address;
   - the maintainer's e-mail address;
   - the Outlook values (optional, see section 4);
   - the app's name.

   It generates every secret and writes `.env` readable by its owner only. **At the end it prints two keys. Store them outside the server now, in two places** (a password manager, a sealed envelope). Without `BACKUP_ENCRYPTION_KEY` no backup can be restored. Without `TWO_FACTOR_ENCRYPTION_KEY` nobody with two-step login can log in. Better still, keep a copy of the whole `.env`.

   `setup.sh` refuses to run when `.env` already exists, because new keys would make the existing backups and two-step logins unusable.
3. Start:
   ```bash
   docker compose pull
   docker compose up -d
   docker compose ps
   ```
   The backend creates the database tables on its first start. After about a minute all four services are up, and `db` and `backend` show `healthy`.
4. Check from the server itself (use the port given to `setup.sh`):
   ```bash
   curl http://127.0.0.1:3000/health
   ```
   The answer is `{"status":"ok"}`.
5. Configure the HTTPS proxy, then open the public address in a browser. The login page appears. Nobody can log in yet.

Every service restarts by itself after a crash or a reboot.

## 3. First data and going live

Installing sends no e-mail. The steps below send mail only to the person doing the checks.

**3.1 Starting data, once.** The club's starting data (administrator, staff, teams, rooms) comes in a file named `seed-data.json`. It contains names, e-mail addresses and the administrator's one-time password, so it travels only over SSH (`scp`), never by e-mail or chat.

To write one from scratch, start from the example in the image, then replace every value, above all the administrator's address and password:
```bash
docker compose run --rm -T --no-deps --entrypoint cat backend prisma/seed-data.example.json > seed-data.json
```

```bash
chmod 644 seed-data.json
docker compose run --rm -v "$PWD/seed-data.json:/app/backend/prisma/seed-data.json:ro" backend npm run db:seed
rm seed-data.json
```

Use `$PWD` exactly as written. Older Compose versions turn a relative path here into an empty volume. Without the file, the command stops and prints the mount it needs. The data now lives in the database and its backups.

A wrong file can be fixed by emptying the database and seeding again, but only before anything real has been entered:
```bash
docker compose down
docker volume rm etofc_pg_data
docker compose up -d
```

**3.2 Checks.** These mail nobody on the staff list. Do not finalize a week and do not invite staff.
- `https://<address>/health` answers `{"status":"ok"}`, and `http://<address>` redirects to HTTPS.
- The administrator logs in with the one-time password, changes it and sets up two-step login.
- E-mail: the administrator invites the checker's own address from the Users page. The mail arrives, and its link opens the public address. Then the administrator deletes that invitation unused.
- PDF: the Planner's print preview renders.
- Outbound access, from the backend container:
  ```bash
  docker compose exec backend node -e "fetch('https://adatbank.mlsz.hu').then(r => console.log(r.status))"
  ```
- Backups: the next morning a new file is in `backups/`, and it opens with the offline copy of the key (section 6.4).

**3.3 Going live (the club's administrator).** Upload the dormitory floor plan, set the planners' permissions, then invite the staff who will use the app from the Users page. Staff who only need the weekly PDF are never invited: they get it anyway. An unused invitation expires after 7 days and can be resent. The first real finalization mails the weekly PDF to everyone.

## 4. Outlook

Outlook calendar sync is off while the Outlook values in `.env` are empty. The rest of the app works normally, and administrators see on their profile that the integration is not set up.

**4.1 Turning it on**
1. In the Microsoft Entra admin center, register an application (or use an existing one):
   - account type: this organization only;
   - redirect URI, platform Web: `https://<address>/api/integrations/outlook/callback`;
   - delegated Microsoft Graph permissions: `offline_access`, `User.Read`, `Calendars.ReadWrite`.

   Create a client secret and **note its expiry date**.
2. Fill in these lines in `.env` (a minimal server may have no editor: `sudo apt install -y nano`, then `nano .env`):
   ```
   OUTLOOK_CLIENT_ID=<application (client) ID>
   OUTLOOK_CLIENT_SECRET='<client secret value>'
   OUTLOOK_CLIENT_SECRET_EXPIRES=2028-10-15
   OUTLOOK_TENANT_ID=<directory (tenant) ID>
   ```
   `OUTLOOK_REDIRECT_URI` was already written by `setup.sh`. The backend refuses to start if the ID and secret are set without a valid expiry date.
3. Apply it:
   ```bash
   docker compose up -d
   ```
   Only the backend is recreated, and the app is unavailable for 10 to 20 seconds. Users stay logged in. Do not use `docker compose restart`: it does not read `.env` again. This holds for every `.env` change.

Turning it off is the reverse: empty the ID and secret, then `docker compose up -d`. Existing connections are kept and work again once it is turned back on.

**4.2 The client secret expires.** The portal allows at most 24 months. The maintainer address gets an e-mail 30, 7 and 1 days before `OUTLOOK_CLIENT_SECRET_EXPIRES`. To rotate:
1. Create a new client secret in the same app registration and note its expiry date.
2. Put the new value in `OUTLOOK_CLIENT_SECRET` and the new date in `OUTLOOK_CLIENT_SECRET_EXPIRES`.
3. Run `docker compose up -d`.
4. Delete the old secret in the portal.

If the secret does expire, sync stops. The nightly check then e-mails the maintainer. Rotating the secret is enough: users do not reconnect.

## 5. Updates

```bash
sh update.sh 1.0.1
```
If the folder is a clone of the public repository, check out the same version first, so the kit files match the images:
```bash
git fetch --tags && git checkout v1.0.1
```

It asks for confirmation, then:
1. downloads the new version's images, unless they are already on the server;
2. takes a backup;
3. restarts on the new version and waits until every service is healthy;
4. deletes images older than the previous version;
5. prints the exact rollback commands.

Database migrations run by themselves when the new backend starts. An update downloads about 650 MB. The previous version's images stay on the server for a rollback until the next update.

**When not to update**
- While someone is finalizing a week: the finalization runs in the backend's memory and a restart loses it.
- Between 01:45 and 04:00, Hungarian time: the nightly backup and jobs run then.

**Rollback.** Migrations cannot be undone, so going back means the previous version plus the backup taken just before the update. `update.sh` prints these commands with the version and the file filled in:
```bash
sed -i 's/^APP_VERSION=.*/APP_VERSION=1.0.0/' .env
docker compose stop backend
docker compose exec -T backup sh /backup.sh restore etofc-20261015T164549Z.dump.age
docker compose up -d
```
Anything entered after the update is lost.

**Security updates.** The images carry their own operating system, Node.js, Chromium, nginx and PostgreSQL. Every release is built on the current base images, so installing a release patches them; when only a base image has a fix, a release of the same code is enough. Update the server's own packages with the distribution's usual tools.

## 6. Backups

**6.1 Schedule.** The `backup` service dumps the database every night at 01:00 UTC into `backups/`, encrypted with `BACKUP_ENCRYPTION_KEY`, and keeps the 14 newest files. Encrypted files are safe to copy anywhere. The files belong to `root`: anyone can read and copy them, but deleting one by hand needs `sudo`.

**6.2 Off the server.** A backup on the same disk does not survive the loss of the server. Copy `backups/` elsewhere every day, for example from another machine:
```bash
rsync -a etofc-server:/opt/etofc/backups/ /srv/etofc-backups/
```

**6.3 Manual backup**
```bash
docker compose exec -T backup sh /backup.sh dump
```

**6.4 Checking a backup without restoring it.** Run this where the copied backups are, for example on the machine that holds the off-server copy. It needs the backup image, so log in to `ghcr.io` there first if the images are private. Put the offline copy of the key (the `AGE-SECRET-KEY-...` text alone) in a file, then:
```bash
docker run --rm -i -v "$PWD/backups:/backups:ro" --entrypoint sh ghcr.io/delilaszlo/eto-backup:<version> \
  -c 'cat > /tmp/key && age -d -i /tmp/key /backups/<file> | pg_restore --list > /dev/null && echo OK' < key.txt
rm key.txt
```
It prints `OK`. A wrong key fails with "no identity matched". On Windows PowerShell, which has no `<`, copy the key to the clipboard and pipe it in instead:
```powershell
Get-Clipboard | docker run --rm -i -v "${PWD}/backups:/backups:ro" --entrypoint sh ghcr.io/delilaszlo/eto-backup:<version> -c 'cat > /tmp/key && age -d -i /tmp/key /backups/<file> | pg_restore --list > /dev/null && echo OK'
```

**6.5 Restore**
```bash
docker compose stop backend
docker compose exec -T backup sh /backup.sh restore <file>
docker compose up -d
```
`restore` refuses while the backend is running. It restores into a separate database and swaps it in only on success, so a failed restore leaves the current data untouched.

**6.6 On a new server.** Copy the old `.env`, do not run `setup.sh`: the same keys are needed for the backups, two-step logins and Outlook connections. Then:
1. Copy the backup file into `backups/`.
2. Run `docker compose up -d`.
3. Restore as in 6.5.

**6.7 Rehearsing a restore on the same server.** A second copy of this folder is the same installation unless it gets its own project name, and its `up` would attach to the live database. So:
1. Copy the folder, for example to `/opt/etofc-drill`, with the live `.env`, and copy one backup file into its `backups/`.
2. Add `COMPOSE_PROJECT_NAME=etofc-drill` to its `.env`, and check that `docker compose config | head -1` prints `name: etofc-drill` before going on.
3. Run `docker compose up -d db backup`, then restore as in 6.5 (the backend is not running here, so skip its `stop`). Do not start the backend or the web server in this folder: with the live `.env`, its nightly jobs would mail the live installation's users.
4. Compare the row counts with the live installation by running this in both folders:
   ```bash
   docker compose exec -T db psql -U eto -d etofc -c "SELECT table_name, (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I', table_name), false, true, '')))[1]::text::int AS rows FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY 1"
   ```
5. Remove the rehearsal: `docker compose down -v` in its folder, then delete the folder.

## 7. Monitoring

- **Uptime:** point an outside monitor (UptimeRobot or the host's own) at `https://<address>/health` and expect `{"status":"ok"}`. This shows that the backend runs. It does not test the database. A monitor that checks every 5 minutes misses short outages, such as an update's restart, and its alert can come up to 5 minutes late.
- **Mail account:** some mail services disable SMTP credentials that go unused for a while, without notice. The maintainer's error mails go through the same account, so nothing reports it. After a long quiet period, such as the summer break, send a test invitation.
- **Backups:** the newest file in `backups/` should be less than 26 hours old:
  ```bash
  find backups -name 'etofc-*.dump.age' -mmin -1560 | grep -q . || echo "no recent backup"
  ```
- **Background jobs:** a failed nightly job e-mails the maintainer address.
- **Logs:** `docker compose logs --tail 200 backend`. Each service keeps three 10 MB log files.

## 8. Maintenance tasks

**Changing the public address**
1. Set the new `FRONTEND_URL` and `OUTLOOK_REDIRECT_URI` in `.env`.
2. Change the redirect URI in the Azure app registration.
3. Update the proxy.
4. Run `docker compose up -d`.

**Running a background job by hand.** The jobs are `outlook-token-health`, `outlook-repair`, `outlook-prune`, `mlsz-refresh` and `dorm-digest`:
```bash
docker compose exec backend node dist/src/jobs/cli.js mlsz-refresh
```

**PostgreSQL 16 is supported until November 2028.** The move to a newer major version ships as an app release with a matching backup image. The procedure:
1. Take a backup and check it (section 6.4).
2. Run `docker compose down`.
3. Run `docker volume rm etofc_pg_data`.
4. Install the release.
5. Run `docker compose up -d db backup`.
6. Restore (section 6.5).
7. Run `docker compose up -d`.

## 9. Troubleshooting

| Symptom | Cause |
| --- | --- |
| `docker compose` stops with "... nincs megadva a .env fájlban" | That line of `.env` is missing or empty |
| The backend restarts over and over, the log says "Hibás éles konfiguráció" | The log line names the `.env` value that is wrong |
| Every login or save fails with 403 | `FRONTEND_URL` is not exactly the address in the browser (scheme, host and port, no trailing slash) |
| Login does not stick over plain HTTP | Session cookies are HTTPS-only. Use the proxy's HTTPS address |
| Everyone gets "Túl sok kérés" at once, even with few users | `TRUST_PROXY_HOPS` is lower than the number of proxies plus one, so all users share one limit |
| Users behind one shared address (the club's Wi-Fi) get "Túl sok kérés" at busy times | The limit is per address: 5000 requests per 15 minutes. Raise it with `RATE_LIMIT_GLOBAL_MAX=<n>` in `.env`, then `docker compose up -d` |
| Floor plan or PDF uploads fail | The proxy's request body limit is under 10 MB |
| The finalization progress freezes, then jumps | The proxy buffers `text/event-stream` |
| No e-mails arrive | `docker compose logs backend`. Also check the sender domain's SPF and DKIM records for the SMTP service |
| Sending an invitation takes about half a minute, then fails | The host blocks the SMTP port. Test it as in section 1 and use another port of the mail service |
| E-mails land in Junk | See the mail service requirements in section 1 |
| `docker run` in section 6.4 fails with "unauthorized" | That machine is not logged in to `ghcr.io` (section 2, step 1) |
| `docker volume ls` shows an unnamed volume beside `etofc_pg_data` | The backup service's own empty volume. Harmless. After `docker compose down -v`, `docker volume prune` removes leftover unnamed volumes and never touches named ones |
| API calls fail with 502 for a few seconds after `up -d` | The backend is still starting. It answers once `docker compose ps` shows it `healthy` |
| `[pdf]` lines about the Chromium sandbox in the log | Expected in a container. PDFs still render |

## 10. Secrets

All secrets are in `.env`, which only its owner can read. Do not change a value unless this table says it is safe.

| Value | What changing it does |
| --- | --- |
| `JWT_SECRET` | Safe at any time. Everyone is logged out |
| `OUTLOOK_STATE_SECRET` | Safe at any time. An Outlook connection started in the last 10 minutes fails and can be retried |
| `TWO_FACTOR_ENCRYPTION_KEY` | **Never change or lose it.** Everyone with two-step login is locked out |
| `OUTLOOK_TOKEN_ENCRYPTION_KEY` | Every connected user has to reconnect Outlook |
| `BACKUP_ENCRYPTION_KEY` | New backups use the new key. Keep the old key as long as backups made with it exist |
| `POSTGRES_PASSWORD` | Run `docker compose exec db psql -U eto -d etofc -c "ALTER ROLE eto WITH PASSWORD '<new>'"`, then put the same value in `.env` and run `docker compose up -d` |
| `SMTP_PASS` | Set by the mail provider. Change it there first, then in `.env` |
| `OUTLOOK_CLIENT_SECRET` | See section 4.2 |
