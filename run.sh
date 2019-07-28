#!/bin/bash
source "$(dirname "$0")/.init.sh"

[[ $EUID = 0 ]] ||
  abort "Root access is needed, please run as root"

message "Installing and configuring dependencies"

set -ex

ln -fs "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
apt-get update &&
DEBIAN_FRONTEND=noninteractive apt-get -y install \
  tzdata \
  gettext-base \
  chromium-browser \
  apache2 \
  libapache2-mod-php \
  php \
  php-mbstring \
  php-imagick \
  php-curl \
  php-gd \
  php-mysql \
  mysql-server \
  s3cmd \
  rsync

dpkg-reconfigure --frontend noninteractive tzdata # maybe not needed

a2enmod rewrite

set +x

if id -u "$KIOSK_USERNAME" &>/dev/null; then
  message "User '$KIOSK_USERNAME' exists already"
else
  message "Adding '$KIOSK_USERNAME' user"
  adduser --disabled-password --gecos "" "$KIOSK_USERNAME"
fi

message "Cofiguring '$KIOSK_USERNAME' user"
KIOSK_HOME="$(getent passwd "$KIOSK_USERNAME" | cut -d: -f6)"
mkdir -p "$KIOSK_HOME/.config/autostart"
envsubst '$SITE_HOST' < templates/chromium-kiosk.desktop > "$KIOSK_HOME/.config/autostart/chromium-kiosk.desktop"
chown -R "$KIOSK_USERNAME" -- "$KIOSK_HOME/.config"

message "Configuring GDM"
[ -f /etc/gdm3/custom.conf-backup ] || cp -- /etc/gdm3/custom.conf /etc/gdm3/custom.conf-backup
envsubst '$KIOSK_USERNAME' < templates/gdm3.conf > /etc/gdm3/custom.conf

message "Shadowing $SITE_HOST with localhost"
hosts_line="127.0.0.1 $SITE_HOST"
hosts_file="/etc/hosts"
grep -qF -- "$hosts_line" "$hosts_file" || echo "$hosts_line" >> "$hosts_file"

message "Refreshing Apache configuration"
#TODO: add MYSQL_DATABASE, MYSQL_USER and MYSQL_PASSWORD here and in template
envsubst '$SITE_HOST $KIOSK_ROOT $HTTP_ROOT' < templates/site.conf > /etc/apache2/sites-enabled/site.conf

message "MySQL not free bar anymore" #TODO: remove me
chmod go-r /etc/mysql/debian.cnf

message "Configuring MySQL user and database"
echo "DROP DATABASE IF EXISTS $MYSQL_DATABASE; CREATE DATABASE $MYSQL_DATABASE;" | mysql --defaults-file=/etc/mysql/debian.cnf
#TODO: using mysql --defaults-file=/etc/mysql/debian.cnf, create user MYSQL_USER with password MYSQL_PASSWORD, with all rights on MYSQL_DATABASE
#TODO: generate a defaults file similar to debian.cnf (the template exists already)

as_user ./sync.sh

message "Restarting Apache"
systemctl restart apache2.service

message "Done. Go edit /etc/hosts if you want to access the real online version of the site!"
