#!/bin/bash

cd -P -- "$(dirname "$0")"
export KIOSK_ROOT="$(pwd)"
export KIOSK_OWNER="$(stat -c "%U" "$KIOSK_ROOT")"

message() {
  echo "[$(date --rfc-3339=seconds)]" "$@"
}

abort() {
  message "$@"
  exit 1
}

as_user() {
  if [[ $EUID = 0 ]]; then
    runuser -u "$KIOSK_OWNER" -- "$@"
  else
    command "$@"
  fi
}

git() {
  as_user git "$@"
}

s3_download() {
  local s3_source="$1"
  local destination="$2"
  local expected_size="$3"

  if [[ -f "$destination" ]]; then
    # s3cmd with --continue flag does not check if the file was completely downloaded
    # that's what we're doing here
    local cur_size="$(stat -c "%s" -- "$destination" 2>/dev/null)"
    [[ $cur_size -eq $expected_size ]] && return 0
  fi

  s3cmd --config="$KIOSK_ROOT/.s3cfg" --continue --progress get "$s3_source" "$destination"
  return $?
}

[ -f .env ] ||
  abort "You need a .env file. See .env.sample for inspiration."

. .env

: ${MYSQL_DATABASE:=kiosk}
: ${MYSQL_USER:=kiosk}
: ${MYSQL_PASSWORD:=verysecret}

message "Owner is '$KIOSK_OWNER'"

if [[ -z $SKIP_UPDATE_CHECK ]]; then
  message "Checking for updates"
  if git fetch; then
    if ! git diff --exit-code --quiet HEAD HEAD@{upstream}; then
      # TODO: in case of updates, we're going to check again immediately... (an additional git fetch)
      git pull --rebase && exec "$0" "$@" ||
        abort "Update error"
    else
      message "Up to date"
    fi
  else
      abort "Error checking for updates"
  fi
fi
