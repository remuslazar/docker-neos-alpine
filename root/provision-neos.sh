#!/usr/bin/env bash
set -ex

function update_settings_yaml() {
  local settings_file=$1

  cd /data/www-provisioned
  create_settings_yaml $settings_file

  [ -f $settings_file ] || return 0

  echo "Configuring $settings_file..."
	sed -i -r "1,/driver:/s/port: .+?/driver: pdo_mysql/g" $settings_file
	sed -i -r "1,/dbname:/s/dbname: .+?/dbname: \"$DB_DATABASE\"/g" $settings_file
	sed -i -r "1,/user:/s/user: .+?/user: \"$DB_USER\"/g" $settings_file
	sed -i -r "1,/password:/s/password: .+?/password: \"$DB_PASS\"/g" $settings_file
	sed -i -r "1,/host:/s/host: .+?/host: \"$DB_HOST\"/g" $settings_file
	sed -i -r "1,/port:/s/port: .+?/port: 3306/g" $settings_file
}

function update_neos_settings() {
  if [ -z "${FLOW_CONTEXT}" ]; then
	  update_settings_yaml Configuration/Settings.yaml
  else
	  update_settings_yaml Configuration/${FLOW_CONTEXT}/Settings.yaml
    if [ "${FLOW_CONTEXT}" = "Development/Behat" ]; then
	    update_settings_yaml Configuration/Testing/Behat/Settings.yaml
    fi
  fi
}

function create_settings_yaml() {
  local settings_file=$1
  mkdir -p /data/www-provisioned/$(dirname $settings_file)
  if [ ! -f /data/www-provisioned/$settings_file ] ; then
    cp /Settings.yaml /data/www-provisioned/$settings_file
  fi
}

# Provision conainer at first run
if [ -f /data/www/composer.json ] || [ -f /data/www-provisioned/composer.json ] || [ -z "$REPOSITORY_URL" -a ! -f "/src/composer.json" ]
then
	echo "Do nothing, initial provisioning done"

	# Update DB Settings to keep them in sync with the docker ENV vars
  update_neos_settings
else
  # Make sure to init xdebug, not to slow-down composer
  /init-xdebug.sh

  # Layout default directory structure
  mkdir -p /data/www-provisioned
  mkdir -p /data/logs
  mkdir -p /data/tmp/nginx

  ###
  # Install into /data/www
  ###
  cd /data/www-provisioned

  if [ "${REPOSITORY_URL}" ] ; then
    git clone -b $VERSION $REPOSITORY_URL .
  else
    rsync -r --exclude node_modules --exclude .git --exclude /Data /src/ .
  fi

  composer install $COMPOSER_INSTALL_PARAMS
  update_neos_settings

  # Set permissions
  chown www-data:www-data -R /tmp/
	chown www-data:www-data -R /data/
	chmod g+rwx -R /data/*

	# Set ssh permissions
	if [ -z "/data/.ssh/authorized_keys" ]
		then
			chown www-data:www-data -R /data/.ssh
			chmod 700 /data/.ssh
			chmod 600 /data/.ssh/authorized_keys
	fi
fi
