#!/bin/sh
set -eu

cd "$(dirname "$0")"
KIT_DIR=$(pwd)
KIT_URL=https://github.com/delilaszlo/eto-resource-scheduler.git
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

read_hidden() {
  printf '%s: ' "$1" >&2
  stty -echo 2> /dev/null || true
  IFS= read -r hidden || { stty echo 2> /dev/null || true; fail "Megszakítva."; }
  stty echo 2> /dev/null || true
  say ""
  printf '%s' "$hidden"
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
      *) [ "$number" -ge "${3:-1}" ] && break ;;
    esac
    say "Legalább ${3:-1} egész szám kell."
  done
  printf '%s' "$number"
}

ask_yes() {
  while :; do
    reply=$(ask "$1 (i/n)" "$2") || exit 1
    case $reply in
      i | I | igen) return 0 ;;
      n | N | nem) return 1 ;;
    esac
  done
}

random_hex() {
  od -An -vtx1 -N"$1" /dev/urandom | tr -d ' \n'
}

git_kit() {
  git -c safe.directory="$KIT_DIR" "$@"
}

env_value() {
  sed -n "s/^$1=//p" .env | tail -n 1 | sed "s/^'\(.*\)'\$/\1/"
}

sql() {
  docker compose exec -T db psql -U "$(env_value POSTGRES_USER)" -d "$(env_value POSTGRES_DB)" -tAc "$1"
}

# 1. Csak rootként, a nyilvános csomag klónjából; a csomag a kért vagy a legújabb kiadott verzióra vált
newest_release() {
  git_kit tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1
}

check_kit() {
  [ "$(id -u)" -eq 0 ] || fail "Rootként futtasd: sudo sh setup.sh"
  command -v git > /dev/null 2>&1 || fail "A git nincs telepítve. Telepítés: apt install git"
  origin=$(git_kit remote get-url origin 2> /dev/null) || origin=
  case $origin in
    *github.com[:/]delilaszlo/eto-resource-scheduler | *github.com[:/]delilaszlo/eto-resource-scheduler.git) ;;
    *) fail "Ez a mappa nem a telepítőcsomag klónja. Telepítés: git clone $KIT_URL /opt/etofc" ;;
  esac
  [ -z "$(git_kit status --porcelain --untracked-files=no)" ] ||
    fail "A csomag fájljai módosultak (git status). Visszaállításuk: git checkout -- ."
  current=$(git_kit describe --tags --exact-match HEAD 2> /dev/null) || current=
  if [ -n "${1:-}" ]; then
    wanted=v${1#v}
  elif [ -n "$current" ]; then
    wanted=$current
  else
    git_kit fetch -q --force --tags origin || fail "Nem sikerült letölteni a verziókat (git fetch)."
    wanted=$(newest_release)
    [ -n "$wanted" ] || fail "Még nincs kiadott verzió. Egy előzetes verzió telepítése: sudo sh setup.sh <verzió>"
  fi
  case $wanted in
    v[0-9]*.[0-9]*.[0-9]*) ;;
    *) fail "Érvénytelen verzió: ${wanted#v}. Példa: sudo sh setup.sh 1.0.0" ;;
  esac
  if [ "$wanted" != "$current" ]; then
    git_kit rev-parse -q --verify "refs/tags/$wanted^{commit}" > /dev/null ||
      git_kit fetch -q --force --tags origin || fail "Nem sikerült letölteni a verziókat (git fetch)."
    git_kit rev-parse -q --verify "refs/tags/$wanted^{commit}" > /dev/null ||
      fail "Nincs ilyen verzió: ${wanted#v}. A verziók listája: git tag"
    say "A csomag a(z) ${wanted#v} verzióra vált."
    git_kit checkout -q "$wanted"
    exec sh "$KIT_DIR/setup.sh" "${wanted#v}"
  fi
  version=${wanted#v}
}

# 2. Ubuntun és Debianon a hiányzó Docker telepítése a Docker saját csomagtárából
apt_family() {
  [ -r /etc/os-release ] || return 1
  # shellcheck disable=SC1091
  . /etc/os-release
  case ${ID:-} in
    ubuntu) codename=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}} ;;
    debian) codename=${VERSION_CODENAME:-} ;;
    *) return 1 ;;
  esac
  [ -n "$codename" ]
}

install_docker() {
  apt-get update -q
  apt-get install -y -q ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/%s %s stable\n' \
    "$(dpkg --print-architecture)" "$ID" "$codename" > /etc/apt/sources.list.d/docker.list
  apt-get update -q
  apt-get install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

ensure_docker() {
  if command -v docker > /dev/null 2>&1 && docker compose version > /dev/null 2>&1; then
    return
  fi
  apt_family || fail "A Docker és a Docker Compose v2 nincs telepítve. Ezen a rendszeren előbb telepítsd őket kézzel."
  ask_yes "A Docker nincs telepítve. Telepítsem a Docker hivatalos csomagtárából" i || fail "A Docker nélkül nem folytatható."
  install_docker
}

ensure_curl() {
  command -v curl > /dev/null 2>&1 && return
  apt_family || fail "A curl nincs telepítve, előbb telepítsd."
  ask_yes "A curl nincs telepítve. Telepítsem" i || fail "A curl nélkül nem folytatható."
  apt-get install -y -q curl
}

# 3. Az idő és a hálózat ellenőrzése
check_clock() {
  synced=$(timedatectl show -p NTPSynchronized --value 2> /dev/null) || synced=
  [ "$synced" = yes ] && return
  say "A rendszeróra nincs szinkronizálva (timedatectl), a belépési kódok időalapúak."
  ask_yes "Folytatod így is" n || fail "Megszakítva. Bekapcsolás: timedatectl set-ntp true"
}

check_networks() {
  [ -f /etc/docker/daemon.json ] && grep -q default-address-pools /etc/docker/daemon.json && return
  clash=$(ip -4 -o addr show scope global 2> /dev/null |
    awk '$2 !~ /^(docker|br-|veth)/ { print $4 }' |
    grep -E '^(172\.(1[6-9]|2[0-9]|3[01])|192\.168)\.' || true)
  [ -z "$clash" ] && return
  say "A gép hálózata ($clash) ütközhet a Docker belső hálózataival. Ilyenkor az /etc/docker/daemon.json fájlban a default-address-pools értékét kell más tartományra állítani."
  ask_yes "Folytatod így is" n || fail "Megszakítva."
}

# 4. A kérdések és a .env, csak az első futáskor; a kulcsokat később soha nem írja újra
ask_address() {
  while :; do
    url=$(ask_required "Az alkalmazás nyilvános címe, például https://eto.example.hu")
    url=${url%/}
    case $url in
      https://*/* | http://*/*) say "Csak a cím kell, útvonal nélkül." ;;
      https://?*) break ;;
      *) say "https:// címmel kezdődjön." ;;
    esac
  done
}

ask_proxy() {
  https_profile=
  trusted_proxies=127.0.0.1/32
  http_bind=127.0.0.1
  http_port=3000
  if ask_yes "A HTTPS-t ez a szerver szolgálja ki a beépített Caddyvel (nem, ha már van saját HTTPS proxy)" i; then
    https_profile=https
    cdns=$(ask_number "Hány CDN áll a szerver előtt (például 1 Cloudflare-rel, 0 ha nincs)" 0 0)
    trust_proxy_hops=$((cdns + 2))
    [ "$cdns" -eq 0 ] || trusted_proxies="0.0.0.0/0 ::/0"
    return
  fi
  proxies=$(ask_number "Hány proxy áll az alkalmazás előtt a saját HTTPS proxyval együtt (például 1, vagy 2 Cloudflare-rel)" 1)
  trust_proxy_hops=$((proxies + 1))
  http_port=$(ask_number "Melyik porton figyeljen az alkalmazás a saját proxy felé" 3000)
  if ! ask_yes "A saját HTTPS proxy ezen a gépen fut" i; then
    http_bind=$(ask_required "Melyik címen érje el a proxy ezt a gépet (0.0.0.0 = minden címen)" 0.0.0.0)
  fi
}

ask_restore_keys() {
  backup_key=
  two_factor_key=
  ask_yes "Egy korábbi telepítés mentését állítod vissza (költözés új szerverre)" n || return 0
  [ -n "$(find backups -maxdepth 1 -name 'etofc-*.dump.age' 2> /dev/null)" ] ||
    fail "Nincs mentés a $KIT_DIR/backups mappában. Másold oda a mentést, majd futtasd újra: sudo sh setup.sh"
  say "A korábbi telepítés két kulcsa kell, amelyet a setup.sh annak idején kiírt."
  while :; do
    backup_key=$(read_hidden "BACKUP_ENCRYPTION_KEY") || exit 1
    case $backup_key in
      AGE-SECRET-KEY-1*) break ;;
    esac
    say "AGE-SECRET-KEY-1 kezdetű kulcs kell."
  done
  while :; do
    two_factor_key=$(read_hidden "TWO_FACTOR_ENCRYPTION_KEY") || exit 1
    [ ${#two_factor_key} -eq 64 ] && case $two_factor_key in *[!0-9a-fA-F]*) false ;; esac && break
    say "64 hexadecimális karakter kell."
  done
}

backup_keygen() {
  docker image inspect "$IMAGE_PREFIX-backup:$version" > /dev/null 2>&1 ||
    docker pull -q "$IMAGE_PREFIX-backup:$version" > /dev/null ||
    fail "Nem sikerült letölteni: $IMAGE_PREFIX-backup:$version"
  docker run --rm --entrypoint age-keygen "$IMAGE_PREFIX-backup:$version" 2> /dev/null | grep '^AGE-SECRET-KEY-' ||
    fail "Nem sikerült mentési kulcsot generálni."
}

write_env() {
  say ""
  ask_restore_keys
  say ""
  ask_address
  ask_proxy
  app_name=$(ask_required "Az alkalmazás neve" "ETO FC Heti Program")
  if [ -z "$backup_key" ]; then
    operator_email=$(ask_email "Az üzemeltető e-mail címe (a konzol belépése és az értesítések)")
    ask_operator_password
  fi

  [ -n "$backup_key" ] || backup_key=$(backup_keygen)
  [ -n "$two_factor_key" ] || two_factor_key=$(random_hex 32)

  umask 077
  cat > .env.tmp << EOF
# setup.sh, $(date -u +%Y-%m-%d)
APP_VERSION=$version
APP_NAME='$app_name'
FRONTEND_URL=$url
TRUST_PROXY_HOPS=$trust_proxy_hops
HTTP_BIND=$http_bind
HTTP_PORT=$http_port
COMPOSE_PROFILES=$https_profile
CADDY_TRUSTED_PROXIES='$trusted_proxies'

# Titkok: a két titkosító kulcsot a szerveren kívül is őrizd meg
JWT_SECRET=$(random_hex 48)
OUTLOOK_STATE_SECRET=$(random_hex 48)
OUTLOOK_TOKEN_ENCRYPTION_KEY=$(random_hex 32)
TWO_FACTOR_ENCRYPTION_KEY=$two_factor_key
BACKUP_ENCRYPTION_KEY=$backup_key

POSTGRES_USER=eto
POSTGRES_PASSWORD=$(random_hex 24)
POSTGRES_DB=etofc
EOF
  mv .env.tmp .env
  say "Kész: .env (csak a tulajdonosa olvashatja)."
}

# Egy korábbi szerverről hozott .env a csomag verzióját kapja
sync_version() {
  current=$(env_value APP_VERSION)
  [ "$current" = "$version" ] && return
  say "A .env verziója $current, a csomagé $version. Futó telepítés frissítésére az update.sh való."
  ask_yes "Átírjam a .env verzióját a csomag verziójára ($version)" i || fail "Megszakítva."
  umask 077
  sed "s/^APP_VERSION=.*/APP_VERSION=$version/" .env > .env.tmp
  cat .env.tmp > .env
  rm -f .env.tmp
}

set_owner() {
  [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ] || return 0
  chown "$SUDO_USER" .env
  getent group docker > /dev/null 2>&1 || return 0
  id -nG "$SUDO_USER" | grep -qw docker && return
  if ask_yes "A(z) $SUDO_USER felhasználó sudo nélkül is kezelje a konténereket (docker csoport)" i; then
    usermod -aG docker "$SUDO_USER"
    say "Újra be kell jelentkeznie, hogy érvényes legyen."
  fi
}

# 5. Tűzfal: előbb az SSH és a webes portok engedélye, csak utána a bekapcsolás
setup_firewall() {
  if ! apt_family; then
    say "A tűzfal beállítása a rendszergazda feladata: az SSH port, HTTPS esetén a 80 és a 443 legyen nyitva."
    return
  fi
  if ! command -v ufw > /dev/null 2>&1; then
    ask_yes "Az ufw tűzfal nincs telepítve. Telepítsem és állítsam be" i || return 0
    apt-get install -y -q ufw
  fi
  ssh_ports=$(sshd -T 2> /dev/null | awk '$1 == "port" { print $2 }' | sort -u | tr '\n' ' ')
  ssh_ports=${ssh_ports% }
  [ -n "$ssh_ports" ] || ssh_ports=22
  ssh_ports=$(ask_required "Az SSH port(ok), szóközzel elválasztva" "$ssh_ports")
  web_ports=
  [ "$(env_value COMPOSE_PROFILES)" = https ] && web_ports="80 443"
  ask_yes "Bekapcsoljam a tűzfalat úgy, hogy csak ezek a portok legyenek nyitva ($ssh_ports${web_ports:+ $web_ports})" i || return 0
  for port in $ssh_ports $web_ports; do
    ufw allow "$port/tcp" > /dev/null
  done
  ufw status | grep -q '^Status: active' || ufw --force enable > /dev/null
}

# 6. Indítás, majd ha kell, a korábbi telepítés legújabb mentésének visszaállítása
start_stack() {
  say "A(z) $version verzió letöltése és indítása..."
  docker compose pull -q
  docker compose up -d --wait --wait-timeout 300 ||
    fail "A szolgáltatások nem indultak el. Napló: docker compose logs"
}

restore_backup() {
  newest=$(find backups -maxdepth 1 -name 'etofc-*.dump.age' 2> /dev/null | sort | tail -n 1)
  [ -n "$newest" ] || return 0
  newest=${newest##*/}
  if [ "$(sql 'select count(*) from "Operator"') $(sql 'select count(*) from "User"')" != "0 0" ]; then
    [ -z "${backup_key:-}" ] || say "Az adatbázis nem üres, a visszaállítás kimarad."
    return 0
  fi
  if [ -n "${backup_key:-}" ]; then
    say "A(z) $newest visszaállítása..."
  else
    ask_yes "Az adatbázis üres, de van mentés. Visszaállítsam a legújabbat ($newest)" n || return 0
  fi
  docker compose stop backend
  docker compose exec -T backup sh /backup.sh restore "$newest" || fail "A visszaállítás nem sikerült."
  docker compose up -d --wait --wait-timeout 300 || fail "A szolgáltatások nem indultak el. Napló: docker compose logs"
}

ask_operator_password() {
  while :; do
    operator_password=$(read_hidden "Az üzemeltető jelszava (legalább 12 karakter)") || exit 1
    if [ ${#operator_password} -lt 12 ]; then
      say "Legalább 12 karakter kell."
      continue
    fi
    again=$(read_hidden "Jelszó újra") || exit 1
    [ "$again" = "$operator_password" ] && break
    say "A két jelszó nem egyezik."
  done
}

# 7. Az üzemeltetői fiók, ha még nincs; a jelszót a backend saját szabályai ellenőrzik
create_operator() {
  [ "$(sql 'select count(*) from "Operator"')" = 0 ] || return 0
  [ -n "${operator_email:-}" ] || operator_email=$(ask_email "Az üzemeltető e-mail címe (a konzol belépése és az értesítések)")
  [ -n "${operator_password:-}" ] || ask_operator_password
  while :; do
    status=0
    printf '%s' "$operator_password" |
      docker compose exec -T backend node dist/src/cli/operator.js create --email "$operator_email" || status=$?
    [ "$status" -eq 0 ] && break
    [ "$status" -eq 2 ] || fail "Nem sikerült létrehozni az üzemeltetői fiókot."
    ask_operator_password
  done
  operator_password=
}

# 8. Várakozás, amíg a beépített Caddy a tanúsítvánnyal HTTPS-en válaszol
wait_for_https() {
  url=$(env_value FRONTEND_URL)
  if [ "$(env_value COMPOSE_PROFILES)" != https ]; then
    curl -fsS --max-time 10 "http://127.0.0.1:$(env_value HTTP_PORT)/health" > /dev/null ||
      say "Az alkalmazás nem válaszol a(z) $(env_value HTTP_PORT) porton. Napló: docker compose logs"
    say "A HTTPS proxy a(z) $url címet a(z) $(env_value HTTP_BIND):$(env_value HTTP_PORT) címre továbbítsa, 10 MB-os kéréstörzzsel, X-Forwarded-For fejléccel és pufferelés nélkül. Minta: proxy/nginx.conf.example, proxy/Caddyfile.example"
    return
  fi
  say "Várakozás a HTTPS tanúsítványra..."
  tries=0
  until curl -fsS --max-time 10 "$url/health" > /dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -ge 18 ]; then
      say "A(z) $url még nem válaszol. A cím DNS rekordja erre a gépre mutasson, és a 80-as és 443-as port legyen elérhető kívülről. Napló: docker compose logs proxy"
      return
    fi
    sleep 10
  done
}

main() {
  check_kit "$@"
  ensure_docker
  ensure_curl
  check_clock
  check_networks
  mkdir -p backups
  if [ -e .env ]; then
    say "Már van .env: a kérdések és a kulcsok kimaradnak, a hátralévő lépések futnak."
    sync_version
  else
    write_env
  fi
  set_owner
  setup_firewall
  start_stack
  restore_backup
  create_operator
  wait_for_https

  say ""
  say "Ezt a két sort tárold el a szerveren kívül is, két helyen (jelszókezelő, lezárt boríték):"
  grep '^BACKUP_ENCRYPTION_KEY=' .env >&2
  grep '^TWO_FACTOR_ENCRYPTION_KEY=' .env >&2
  say "Ha a szerver vagy a .env elvész, ezek nélkül a mentések nem állíthatók vissza."
  say ""
  say "A konzol: $(env_value FRONTEND_URL)/console"
}

main "$@"
