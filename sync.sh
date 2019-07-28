#!/bin/bash
source "$(dirname "$0")/.init.sh"

if [[ $EUID = 0 ]]; then
  message "Running as $KIOSK_OWNER"
  as_user "$0" "$@"
  exit $?
fi

message "Looking for the last backup"

s3_ls_line="$(s3cmd --config="$KIOSK_ROOT/.s3cfg" ls "$AWS_S3_PREFIX" | tail -1)"
s3_object_regex='([[:digit:]]+)[[:blank:]]+(s3://.+/([^/]+\.tar.bz2))$'
[[ $s3_ls_line =~ $s3_object_regex ]] ||
  abort "Something went wrong while listing data in S3 bucket"

s3_object_size="${BASH_REMATCH[1]}"
s3_object_addr="${BASH_REMATCH[2]}"
s3_object_name="${BASH_REMATCH[3]}"
backup_archive="data/downloads/$s3_object_name"

last_downloaded_file="data/last_downloaded.txt"

if [[ $s3_object_addr = "$(<"$last_downloaded_file")" ]]; then
  message "Backup already extracted. Skipping download/extraction."
else
  s3_download "$s3_object_addr" "$backup_archive" $s3_object_size ||
    abort "Something went wrong while downloading backup from S3"

  restore_dir="data/site_tmp"
  mkdir -p "$restore_dir"
  message "Extracting archive"
  if ! tar -xjf "$backup_archive" --directory "$restore_dir"; then
      message "Backup not correctly restored! Cleaning up"
      rm -rf "$restore_dir"
      exit 1
  fi

  site_dir="data/site"
  rm -rf "$site_dir"
  mv -- "$restore_dir" "$site_dir" ||
    abort "Error while moving restored files over the old version"

  echo "$s3_object_addr" > "$last_downloaded_file"
fi

if [[ $MYSQL_DUMP ]]; then
  message "Importing database"
  #TODO: use the right defaults-file
  mysql --defaults-file=/etc/mysql/debian.cnf "$MYSQL_DATABASE" < "$site_dir/$MYSQL_DUMP" ||
    abort "Error importing database"
fi

rsync -a --progress "data/override/" "$site_dir/" ||
  abort "Error applying changes from data/override"
