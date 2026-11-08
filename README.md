# ETO FC Heti Program operations guide

[Magyar nyelvű változat](README.hu.md)

ETO FC Heti Program is the weekly schedule web app of the ETO FC football club. This kit installs it on a server with Docker. The steps start from a freshly installed, empty server. After the installation, most of the operation happens in the operator console at `https://<address>/console`. The license is MIT, see [LICENSE](LICENSE).

## 1. Requirements

- An x86-64 server with Ubuntu 22.04, 24.04 or Debian 12, 13.
- At least 2 CPU cores, 4 GB RAM and 20 GB free disk.
- A domain name, such as `eto.example.hu`. Its DNS record has to point to the server before the installation.
- An SMTP mail account.
- Recommended. SSH set up before the installation, with key login and password login turned off.
- Optional. A Microsoft Entra app registration for the Outlook sync, and an S3-compatible storage for the cloud backups.

## 2. Installation

```bash
sudo apt update && sudo apt install -y git
sudo git clone https://github.com/delilaszlo/eto-resource-scheduler.git /opt/etofc
cd /opt/etofc
sudo sh setup.sh
```

The script installs the newest version. A specific version is installed by adding its number, such as `sudo sh setup.sh 1.0.0`.

The script asks the following questions in Hungarian. A value in square brackets is the default, which Enter accepts.

| Question | Example answer | Note |
| --- | --- | --- |
| Docker is not installed. Install it from Docker's official repository | `i` | Only when Docker is missing |
| curl is not installed. Install it | `i` | Only when curl is missing |
| Continue anyway | `n` | Only after a clock or network warning. The warning names the fix |
| Are you restoring a backup of an earlier installation (moving to a new server) | `n` | `i` only when moving, see section 5 |
| The public address of the app, for example https://eto.example.hu | `https://eto.example.hu` | |
| This server serves HTTPS with the built-in Caddy (no if there is already an own HTTPS proxy) | `i` | With `n`, the questions of the next table follow |
| How many CDNs stand in front of the server (for example 1 with Cloudflare, 0 if none) | `0` | |
| The name of the app | Enter | Default `ETO FC Heti Program`. It appears in the e-mail subjects |
| The operator's e-mail address (console login and notifications) | `uzemelteto@example.hu` | |
| The operator's password (at least 12 characters), then again | | Hidden while typing |
| User `admin` may manage the containers without sudo (docker group) | `i` | Only when run with sudo. Takes effect at the user's next login |
| The ufw firewall is not installed. Install and set it up | `i` | Only when ufw is missing |
| The SSH port(s), separated by spaces | Enter | The default is the port the SSH server listens on |
| Turn on the firewall with only these ports open (22 80 443) | `i` | |

With an own HTTPS proxy in front of the app, these questions come instead of the CDN question.

| Question | Example answer | Note |
| --- | --- | --- |
| How many proxies stand in front of the app, the own HTTPS proxy included (for example 1, or 2 with Cloudflare) | `1` | |
| Which port the app listens on for the own proxy | `3000` | |
| The own HTTPS proxy runs on this machine | `i` | |
| Which address of this machine the proxy uses (0.0.0.0 = every address) | `10.0.0.5` | Only after `n` to the previous question |

At the end the script prints `BACKUP_ENCRYPTION_KEY` and `TWO_FACTOR_ENCRYPTION_KEY`. They are in `.env` as well. If the server or `.env` is lost, a backup can only be restored with these two keys, so they have to be stored outside the server too, for example in a password manager.

If the script stops halfway, it can be run again after the fix. It continues where it stopped and keeps the keys.

## 3. First steps in the console

The console is at `https://<address>/console`, with the operator's e-mail address and password. The first login sets up two-step login with an authenticator app. The Overview page then lists the missing settings. The off-site copy of the backups is described in section 4.

### Mail

The mail settings are under Settings, Mail. Until they are set, the app sends no e-mail. Before saving, a test mail goes to the operator's address.

| Field | Example | Note |
| --- | --- | --- |
| SMTP server | `smtp.example.hu` | Given by the mail provider |
| Port | `587` | Given by the mail provider |
| Username | `heti@example.hu` | Empty if the server needs no login |
| Password | | The mail account's password |
| Sender address | `heti@example.hu` | The mail provider has to allow sending from it |
| Sender name | `ETO FC Heti Program` | |

### Starting data

The card on the Overview page offers an example file. The filled file is uploaded on the same card, once, while the club has no users. Before saving, a preview shows the problems.

`seededUsers` log in with the password given in the file. `invitedUsers` are invited by the club's admins. After the passwords are sent out, the file has to be deleted.

### Outlook

The Outlook settings are under Settings, Outlook. The Outlook sync needs an app registration. The registration is made in the Microsoft Entra admin center (`entra.microsoft.com`) with these steps.

1. App registrations, New registration.
2. Name `ETO FC Heti Program`. Supported account types "Accounts in any organizational directory and personal Microsoft accounts" if any Microsoft account may connect. "Accounts in this organizational directory only" if only the accounts of one organization may.
3. Redirect URI with platform Web. The value is the console's Redirect URI field, such as `https://eto.example.hu/api/integrations/outlook/callback`.
4. API permissions, Add a permission, Microsoft Graph, Delegated permissions. `offline_access`, `User.Read` and `Calendars.ReadWrite` have to be added.
5. Certificates & secrets, New client secret. The expiry can be at most 24 months. The secret's Value is shown only once.

| Field | Example | Note |
| --- | --- | --- |
| Application ID | `0f3c9a2e-5b1d-4c7e-9a8f-2d6b4e1c7a90` | Application (client) ID on the app's Overview page |
| Tenant ID | `common` | `common` if any Microsoft account may connect. If only the accounts of one organization may, the Directory (tenant) ID from the app's Overview page |
| Client secret | | The Value of the new secret, not its Secret ID |
| Secret expiry | `2028-11-01` | The expiry date of the secret |

Before saving, the console checks the ID and the secret with Azure. The console sends an e-mail before the secret expires. A new secret is made with step 5 and entered in the same two fields.

## 4. Backups

The database is backed up every night at 02:00 Hungarian time, or 03:00 in summer time. The backups are encrypted with `BACKUP_ENCRYPTION_KEY`. The server keeps them for 14 days, at most 21 at a time. The Backups page of the console can make a backup on demand, and every backup can be downloaded there.

### Off-site copy

A backup on the server is lost with the server. So at 03:40 every night the console uploads the new backups to an S3-compatible storage, at most 14 in a week. The settings are under Settings, Off-site copy. The example here is Backblaze B2, because its first 10 GB are free, and that is enough for the club's backups.

The Backblaze B2 storage is set up with these steps.

1. Sign up at `backblaze.com` with region EU Central. The region can only be chosen at sign-up, and it keeps the club's data in the EU.
2. Buckets, Create a Bucket. A unique name such as `eto-mentesek`, Files in Bucket Private, Object Lock Enable.
3. The bucket's Object Lock setting, default retention 7 days. Nobody can delete a backup for a week, not even with a stolen key.
4. The bucket's Lifecycle Settings, custom rule. Days till hide 8, days till delete 1. Old backups do not pile up after the lock expires.
5. Application Keys, Add a New Application Key. Access to this bucket only, type of access Write Only. The server can upload but cannot delete. Backblaze shows the key only once.

| Field | Example | Note |
| --- | --- | --- |
| S3 endpoint | `https://s3.eu-central-003.backblazeb2.com` | The Endpoint shown in the bucket list, with `https://` in front |
| Region | `eu-central-003` | The middle part of the endpoint |
| Bucket name | `eto-mentesek` | |
| Folder in the bucket | `etofc` | Optional. Empty uploads to the bucket's root |
| Key ID | `0031a2b3c4d5e6f0000000001` | The keyID of the new key |
| Secret key | | The applicationKey of the new key |

Before saving, the console uploads a test file to the bucket.

### Restoring a backup

A backup is restored on the server with four commands. The Backups page shows them for every backup, with its file name.

```bash
cd /opt/etofc
sudo docker compose stop backend
sudo docker compose exec -T backup sh /backup.sh restore etofc-20261107T010000Z.dump.age
sudo docker compose up -d --wait
```

The restore goes into a separate database first. A failed restore leaves the current data untouched.

## 5. Moving to a new server

A move needs the newest backup and the two saved keys. The backup can be downloaded from the S3 bucket or from the old console. The domain's DNS record has to point to the new server before the installation.

The backup is first copied onto the new server. From there it goes into the kit's `backups` folder before the installation, which otherwise uses the commands of section 2.

```bash
sudo apt update && sudo apt install -y git
sudo git clone https://github.com/delilaszlo/eto-resource-scheduler.git /opt/etofc
sudo mkdir /opt/etofc/backups
sudo cp ~/etofc-*.dump.age /opt/etofc/backups/
cd /opt/etofc
sudo sh setup.sh
```

Compared with section 2, these questions differ.

| Question | Example answer | Note |
| --- | --- | --- |
| Are you restoring a backup of an earlier installation (moving to a new server) | `i` | |
| `BACKUP_ENCRYPTION_KEY` | `AGE-SECRET-KEY-1…` | The saved key, hidden while typing |
| `TWO_FACTOR_ENCRYPTION_KEY` | 64 hexadecimal characters | The saved key, hidden while typing |

The operator's e-mail address and password are not asked, because the operator account comes back with the backup. After the start, the script restores the newest backup of the `backups` folder. The console settings come back with it.

The new `.env` gets a new `JWT_SECRET` and a new `OUTLOOK_TOKEN_ENCRYPTION_KEY`. So everybody has to log in again, and the users who connected Outlook have to connect it again. If the old `.env` survived, it can be copied into `/opt/etofc` before `setup.sh`, and then none of this is needed. The script then asks whether to restore the newest backup, and the answer is `i`.

An old server that still runs has to be shut down, otherwise both servers send the e-mails.

## 6. Updating

```bash
cd /opt/etofc
sudo sh update.sh X.Y.Z
```

`X.Y.Z` is a released version number, such as `1.2.0`. The versions are listed on [GitHub](https://github.com/delilaszlo/eto-resource-scheduler/tags). The console's Status page shows the newest one, and the operator gets an e-mail about every new version.

The script makes a backup, then starts the new version and waits until it is ready. If the new version does not start, the script prints the commands that return to the old version and its backup. No update should run while somebody is finalizing a week, or between 01:45 and 04:00 Hungarian time, when the nightly jobs run.

## 7. Troubleshooting

### During the installation

| Problem | Cause | Solution |
| --- | --- | --- |
| The address does not answer yet | The DNS record does not point to the server, or the hosting provider blocks ports 80 and 443 | Fix the DNS record or the ports, then run `setup.sh` again. The proxy log shows the details |
| The services did not start | Usually a wrong value in `.env` | The backend log names the problem |
| A download failed | The server cannot reach `ghcr.io` or `download.docker.com` | Allow outgoing HTTPS on the server |

The logs are shown by these commands.

```bash
cd /opt/etofc
sudo docker compose logs proxy
sudo docker compose logs backend
```

### During operation

Errors of the running app are on the console's System log page.

| Problem | Cause | Solution |
| --- | --- | --- |
| No e-mails arrive | A wrong mail setting, or the hosting provider blocks port 587 | The Status page shows the last mail error. Another port of the mail provider, such as 2525, can help |
| The e-mails land in spam | The sender's domain has no SPF, DKIM or DMARC record | Add the mail provider's records to the domain |
| Every login fails with a 403 error | `FRONTEND_URL` in `.env` differs from the address in the browser | Correct `FRONTEND_URL` |
| Everybody gets a "Túl sok kérés" error | The club's network shares one address | Raise the limit in Settings, Rate limit |
| The Outlook sync stopped | The Azure secret expired | Make a new secret in the Entra admin center and enter it, see section 3 |
| A club admin lost their phone or password | | Club admins, Recover. The admin gets a password reset link |
| The operator lost their phone | | The "Nem tudsz bejelentkezni?" link on the login page sends an e-mail that turns off two-step login |
| The operator lost both password and phone | | The command below |

This command sets a new operator password and turns off two-step login. It asks for the new password twice.

```bash
cd /opt/etofc
sudo docker compose exec backend node dist/src/cli/operator.js reset
```

## 8. The .env file

`setup.sh` writes the server's settings and secrets into `/opt/etofc/.env`. Only its owner can read it. After a change, `sudo docker compose up -d` restarts the app with the new values.

| Value | Purpose | Example | Change |
| --- | --- | --- | --- |
| `APP_VERSION` | The running version | `1.2.0` | Only through `update.sh` |
| `APP_NAME` | The app's name in the e-mails | `'ETO FC Heti Program'` | Any time |
| `FRONTEND_URL` | The public address | `https://eto.example.hu` | The DNS record and the Azure redirect URI have to change too |
| `TRUST_PROXY_HOPS` | How many proxies a request passes before the backend. The backend finds the visitor's address with it, for the rate limit | `2` with Caddy, `3` with Caddy and Cloudflare, `2` with one own proxy | Adding a CDN raises it by one, removing it lowers it by one |
| `HTTP_BIND`, `HTTP_PORT` | The address and port the app listens on for an own proxy | `127.0.0.1`, `3000` | The own proxy has to forward to the new address too |
| `COMPOSE_PROFILES` | `https` runs the built-in Caddy. Empty means an own proxy | `https` | A switch changes `TRUST_PROXY_HOPS` too |
| `CADDY_TRUSTED_PROXIES` | Where Caddy accepts the visitor's address from | `'127.0.0.1/32'` without CDN, `'0.0.0.0/0 ::/0'` with CDN | Changes together with `TRUST_PROXY_HOPS` when a CDN is added or removed |
| `JWT_SECRET` | Signs the logins | 96 hexadecimal characters | Possible, but everybody is logged out, the operator too |
| `OUTLOOK_STATE_SECRET` | Signs an Outlook connection in progress, valid for 10 minutes | 96 hexadecimal characters | Possible. Only a connection started in the last 10 minutes fails |
| `OUTLOOK_TOKEN_ENCRYPTION_KEY` | Encrypts the Outlook connections | 64 hexadecimal characters | Possible, but every user has to connect Outlook again |
| `TWO_FACTOR_ENCRYPTION_KEY` | Encrypts the two-step logins and the console settings | 64 hexadecimal characters | **Never.** The two-step logins and the console settings are lost |
| `BACKUP_ENCRYPTION_KEY` | Encrypts the backups | `AGE-SECRET-KEY-1…` | Possible. The old backups still need the old key |
| `POSTGRES_USER`, `POSTGRES_DB` | The database's user and name | `eto`, `etofc` | Never |
| `POSTGRES_PASSWORD` | The database's password | 48 hexadecimal characters | In the database first, see below |

The database password changes in three steps. The first command sets it in the database. Then the same password goes into `POSTGRES_PASSWORD` in `.env`. The second command restarts the app.

```bash
cd /opt/etofc
sudo docker compose exec db psql -U eto -d etofc -c "ALTER ROLE eto WITH PASSWORD 'UJ_JELSZO'"
sudo docker compose up -d
```
