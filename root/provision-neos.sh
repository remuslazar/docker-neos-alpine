#!/usr/bin/env bash
set -ex

function update_settings_yaml() {
  local settings_file=$1

  [ -f $settings_file ] || return 0

  echo "Configuring $settings_file..."
	sed -i -r "1,/driver:/s/port: .+?/driver: pdo_mysql/g" $settings_file
	sed -i -r "1,/dbname:/s/dbname: .+?/dbname: \"$DB_DATABASE\"/g" $settings_file
	sed -i -r "1,/user:/s/user: .+?/user: \"$DB_USER\"/g" $settings_file
	sed -i -r "1,/password:/s/password: .+?/password: \"$DB_PASS\"/g" $settings_file
	sed -i -r "1,/host:/s/host: .+?/host: \"$DB_HOST\"/g" $settings_file
	sed -i -r "1,/port:/s/port: .+?/port: 3306/g" $settings_file
}

# Provision conainer at first run
if [ -f /data/www/composer.json ] || [ -f /data/www-provisioned/composer.json ] || [ -z "$REPOSITORY_URL" ]
then
	echo "Do nothing, initial provisioning done"
	# Update DB Settings to keep them in sync with the docker ENV vars
	update_settings_yaml /data/www-provisioned/Configuration/Settings.yaml
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
    git clone -b $VERSION $REPOSITORY_URL .
    composer install $COMPOSER_INSTALL_PARAMS

    # Apply beard patches
    if [ -f /data/www-provisioned/beard.json ]
        then
            beard patch
    fi

    ###
    # Tweak DB connection settings
    ###
    mkdir -p /data/www-provisioned/Configuration
		if [ ! -f /data/www-provisioned/Configuration/Settings.yaml ] ; then
			cp /Settings.yaml /data/www-provisioned/Configuration/
		fi

		update_settings_yaml /data/www-provisioned/Configuration/Settings.yaml

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
