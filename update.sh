#!/bin/sh
set -eu

cd "$(dirname "$0")"
IMAGE_PREFIX=ghcr.io/delilaszlo/eto

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

set_version() {
  sed "s/^APP_VERSION=.*/APP_VERSION=$1/" .env > .env.tmp
  cat .env.tmp > .env
  rm -f .env.tmp
}

[ $# -eq 1 ] || fail "Használat: sh update.sh <verzió>, például: sh update.sh 1.0.1"
new=${1#v}
[ -f .env ] || fail "Nincs .env, előbb a setup.sh kell."
old=$(sed -n 's/^APP_VERSION=//p' .env)
[ -n "$old" ] || fail "A .env nem tartalmaz APP_VERSION sort."

printf 'Frissítés: %s -> %s. Véglegesítés alatt, valamint 01:45 és 04:00 között ne frissíts. Folytatod? (i/n) ' "$old" "$new"
read -r answer || fail "Megszakítva."
case $answer in
  i | I | igen) ;;
  *) fail "Megszakítva." ;;
esac

for image in $(APP_VERSION=$new docker compose config --images); do
  if ! docker image inspect "$image" > /dev/null 2>&1; then
    echo "Letöltés..."
    APP_VERSION=$new docker compose pull -q
    break
  fi
done

echo "Mentés a frissítés előtt..."
dump=$(docker compose exec -T backup sh /backup.sh dump) || fail "A mentés nem sikerült, a frissítés elmaradt."
backup_file=$(printf '%s\n' "$dump" | sed -n 's/.*kesz: \([^ ]*\).*/\1/p')
echo "$dump"

umask 077
set_version "$new"

rollback="Visszaállás a $old verzióra és a frissítés előtti adatokra:
  sed -i 's/^APP_VERSION=.*/APP_VERSION=$old/' .env
  docker compose stop backend
  docker compose exec -T backup sh /backup.sh restore $backup_file
  docker compose up -d"

echo "Indítás..."
if ! docker compose up -d --wait --wait-timeout 300; then
  echo "Az új verzió nem indult el. Napló: docker compose logs backend" >&2
  echo "$rollback" >&2
  exit 1
fi

docker image ls --format '{{.Repository}}:{{.Tag}}' |
  grep "^$IMAGE_PREFIX-" |
  grep -v -e ":$new\$" -e ":$old\$" |
  xargs -r docker image rm > /dev/null || true

echo "Kész: a $new fut."
echo "$rollback"
