#!/bin/sh
set -eu

cd "$(dirname "$0")"
IMAGE_PREFIX=ghcr.io/delilaszlo/eto

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

say() {
  printf '%s\n' "$1" >&2
}

ask() {
  if [ -n "${2:-}" ]; then
    printf '%s [%s]: ' "$1" "$2" >&2
  else
    printf '%s: ' "$1" >&2
  fi
  IFS= read -r answer || fail "Megszakítva."
  [ -n "$answer" ] || answer=${2:-}
  case $answer in
    *"'"*) say "Aposztróf nem lehet benne."; ask "$@"; return ;;
  esac
  printf '%s' "$answer"
}

ask_required() {
  while :; do
    value=$(ask "$@")
    [ -n "$value" ] && break
    say "Kötelező."
  done
  printf '%s' "$value"
}

ask_secret() {
  while :; do
    printf '%s: ' "$1" >&2
    stty -echo 2>/dev/null || true
    IFS= read -r secret || { stty echo 2>/dev/null || true; fail "Megszakítva."; }
    stty echo 2>/dev/null || true
    say ""
    case $secret in
      "") say "Kötelező." ;;
      *"'"*) say "Aposztróf nem lehet benne." ;;
      *) break ;;
    esac
  done
  printf '%s' "$secret"
}

ask_email() {
  while :; do
    email=$(ask_required "$@")
    case $email in
      *" "*) ;;
      ?*@?*.?*) break ;;
    esac
    say "Ez nem e-mail cím."
  done
  printf '%s' "$email"
}

ask_number() {
  while :; do
    number=$(ask_required "$@")
    case $number in
      *[!0-9]*) ;;
      *) [ "$number" -gt 0 ] && break ;;
    esac
    say "Pozitív egész szám kell."
  done
  printf '%s' "$number"
}

ask_yes() {
  while :; do
    case $(ask "$1 (i/n)" "$2") in
      i|I|igen) return 0 ;;
      n|N|nem) return 1 ;;
    esac
  done
}

random_hex() {
  od -An -vtx1 -N"$1" /dev/urandom | tr -d ' \n'
}

[ $# -eq 1 ] || fail "Használat: sh setup.sh <verzió>, például: sh setup.sh 1.0.0"
version=${1#v}

command -v docker > /dev/null 2>&1 || fail "A docker nincs telepítve."
docker compose version > /dev/null 2>&1 || fail "A Docker Compose v2 (docker compose) nincs telepítve."
[ -f docker-compose.yaml ] || fail "A docker-compose.yaml nincs a setup.sh mellett."
[ ! -e .env ] || fail "Már van .env ebben a mappában, a setup.sh nem írja felül. Új kulcsokkal a meglévő mentések és a kétlépcsős azonosítás használhatatlanná válnak."

if ! docker image inspect "$IMAGE_PREFIX-backup:$version" > /dev/null 2>&1; then
  say "A $version verzió mentési képének letöltése..."
  docker pull -q "$IMAGE_PREFIX-backup:$version" > /dev/null ||
    fail "Nem sikerült letölteni: $IMAGE_PREFIX-backup:$version. Privát képek esetén előbb: docker login ghcr.io"
fi
backup_key=$(docker run --rm --entrypoint age-keygen "$IMAGE_PREFIX-backup:$version" 2> /dev/null | grep '^AGE-SECRET-KEY-') ||
  fail "Nem sikerült mentési kulcsot generálni."

say ""
say "Cím"
while :; do
  url=$(ask_required "Az alkalmazás nyilvános címe, például https://eto.example.hu")
  url=${url%/}
  case $url in
    https://*/* | http://*/*) say "Csak a cím kell, útvonal nélkül." ;;
    https://?*) break ;;
    http://localhost | http://localhost:* | http://127.0.0.1 | http://127.0.0.1:*) break ;;
    *) say "https:// címmel kezdődjön, http csak localhost esetén lehet." ;;
  esac
done

http_port=$(ask_number "Ezen a gépen melyik porton figyeljen az alkalmazás" 3000)
http_bind=127.0.0.1
trust_proxy_hops=1
case $url in
  https://*)
    proxies=$(ask_number "Hány HTTPS proxy áll az alkalmazás előtt" 1)
    trust_proxy_hops=$((proxies + 1))
    if ! ask_yes "Az alkalmazáshoz legközelebbi proxy ezen a gépen fut" i; then
      http_bind=$(ask_required "Melyik címén érje el a proxy ezt a gépet (0.0.0.0: mindegyiken)" 0.0.0.0)
      say "A $http_port portot tűzfalon csak a proxy gépe érje el, lásd a README tűzfalról szóló részét."
    fi
    ;;
esac

say ""
say "Levelezés"
smtp_host=$(ask_required "SMTP szerver")
smtp_port=$(ask_number "SMTP port" 587)
smtp_user=$(ask "SMTP felhasználó (Enter: bejelentkezés nélkül)")
smtp_pass=
[ -z "$smtp_user" ] || smtp_pass=$(ask_secret "SMTP jelszó")
email_from=$(ask_email "Feladó címe")
maintainer_email=$(ask_email "Az üzemeltető címe (hibák, lejáró Azure titok)")

say ""
say "Outlook (Enter: kihagyás, később is beállítható)"
outlook_id=$(ask "Azure alkalmazás (kliens) azonosító")
outlook_secret=
outlook_expires=
outlook_tenant=common
if [ -n "$outlook_id" ]; then
  outlook_secret=$(ask_secret "Azure ügyfélkulcs (client secret) értéke")
  while :; do
    outlook_expires=$(ask_required "Az ügyfélkulcs lejárati napja (ÉÉÉÉ-HH-NN)")
    case $outlook_expires in
      [0-9][0-9][0-9][0-9]-[01][0-9]-[0-3][0-9]) break ;;
    esac
    say "ÉÉÉÉ-HH-NN alakban, például 2028-10-15."
  done
  outlook_tenant=$(ask_required "Azure tenant azonosító" common)
fi

say ""
app_name=$(ask_required "Az alkalmazás neve" "ETO FC Heti Program")

umask 077
cat > .env.tmp << EOF
# setup.sh, $(date -u +%Y-%m-%d)
APP_VERSION=$version
APP_NAME='$app_name'
FRONTEND_URL=$url
TRUST_PROXY_HOPS=$trust_proxy_hops
HTTP_BIND=$http_bind
HTTP_PORT=$http_port

# Titkok: a két titkosító kulcsot a szerveren kívül is őrizd meg
JWT_SECRET=$(random_hex 48)
OUTLOOK_STATE_SECRET=$(random_hex 48)
OUTLOOK_TOKEN_ENCRYPTION_KEY=$(random_hex 32)
TWO_FACTOR_ENCRYPTION_KEY=$(random_hex 32)
BACKUP_ENCRYPTION_KEY=$backup_key

POSTGRES_USER=eto
POSTGRES_PASSWORD=$(random_hex 24)
POSTGRES_DB=etofc

SMTP_HOST=$smtp_host
SMTP_PORT=$smtp_port
SMTP_USER='$smtp_user'
SMTP_PASS='$smtp_pass'
EMAIL_FROM_ADDRESS=$email_from
MAINTAINER_EMAIL=$maintainer_email

OUTLOOK_CLIENT_ID=$outlook_id
OUTLOOK_CLIENT_SECRET='$outlook_secret'
OUTLOOK_CLIENT_SECRET_EXPIRES=$outlook_expires
OUTLOOK_TENANT_ID=$outlook_tenant
OUTLOOK_REDIRECT_URI=$url/api/integrations/outlook/callback
EOF
mv .env.tmp .env

say ""
say "Kész: .env (csak a tulajdonosa olvashatja)."
say ""
say "Ezt a két sort most tárold el a szerveren kívül is, két helyen:"
grep '^BACKUP_ENCRYPTION_KEY=' .env >&2
grep '^TWO_FACTOR_ENCRYPTION_KEY=' .env >&2
say "Az első nélkül a mentések nem állíthatók vissza, a második nélkül a kétlépcsős azonosítást használók nem tudnak belépni."
say ""
say "Következő lépés:"
say "  docker compose pull"
say "  docker compose up -d"
