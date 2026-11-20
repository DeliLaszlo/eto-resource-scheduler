#!/bin/sh
# Frissítés a szerveren: a csomag a célverzióra vált, majd letöltés, mentés és indítás az új verzióval.

set -eu

cd "$(dirname "$0")"
KIT_DIR=$(pwd)
IMAGE_PREFIX=ghcr.io/delilaszlo/eto

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

git_kit() {
  git -c safe.directory="$KIT_DIR" "$@"
}

set_version() {
  sed "s/^APP_VERSION=.*/APP_VERSION=$1/" .env > .env.tmp
  cat .env.tmp > .env
  rm -f .env.tmp
}

confirm() {
  printf 'Frissítés: %s -> %s. Véglegesítés alatt, valamint 01:45 és 04:00 között ne frissíts. Folytatod? (i/n) ' "$old" "$new"
  read -r answer || fail "Megszakítva."
  case $answer in
    i | I | igen) ;;
    *) fail "Megszakítva." ;;
  esac
}

# 1. A csomag a célverzió címkéjére vált, és onnan az új update.sh folytatja
switch_kit() {
  [ -z "$(git_kit status --porcelain --untracked-files=no)" ] ||
    fail "A csomag fájljai módosultak (git status). Visszaállításuk: git checkout -- ."
  git_kit fetch -q --force --tags origin || fail "Nem sikerült letölteni a verziókat (git fetch)."
  git_kit rev-parse -q --verify "refs/tags/v$new^{commit}" > /dev/null ||
    fail "Nincs ilyen verzió: v$new. A verziók listája: git tag"
  confirm
  git_kit checkout -q "v$new"
  exec env ETO_UPDATE_FROM="$old" sh "$KIT_DIR/update.sh" "$new"
}

# 2. Letöltés, mentés, indítás az új verzióval
apply_update() {
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

  rollback="Visszaállás a(z) $old verzióra és a frissítés előtti adatokra:
  cd $KIT_DIR
  sudo git -c safe.directory=$KIT_DIR checkout -q v$old
  sudo sed -i 's/^APP_VERSION=.*/APP_VERSION=$old/' .env
  sudo docker compose stop backend
  sudo docker compose exec -T backup sh /backup.sh restore $backup_file
  sudo docker compose up -d --wait"

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

  echo "Kész: a(z) $new fut."
  echo "$rollback"
}

main() {
  [ "$(id -u)" -eq 0 ] || fail "Rootként futtasd: sudo sh update.sh <verzió>"
  [ $# -eq 1 ] || fail "Használat: sudo sh update.sh <verzió>, például: sudo sh update.sh 1.0.1"
  new=${1#v}
  [ -f .env ] || fail "Nincs .env, előbb a setup.sh kell."
  if [ -n "${ETO_UPDATE_FROM:-}" ]; then
    old=$ETO_UPDATE_FROM
    apply_update
    return
  fi
  old=$(sed -n 's/^APP_VERSION=//p' .env)
  [ -n "$old" ] || fail "A .env nem tartalmaz APP_VERSION sort."
  switch_kit
}

main "$@"
