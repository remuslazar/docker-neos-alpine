#!/usr/bin/env bash
set -ex

function update_settings_yaml() {
  local settings_file=$1
  local db_host=$2

  cd /data/www-provisioned

  [ -f $settings_file ] || return 0

  echo "Configuring $settings_file..."
	sed -i -r "1,/driver:/s/port: .+?/driver: pdo_mysql/g" $settings_file
	sed -i -r "1,/dbname:/s/dbname: .+?/dbname: \"$DB_DATABASE\"/g" $settings_file
	sed -i -r "1,/user:/s/user: .+?/user: \"$DB_USER\"/g" $settings_file
	sed -i -r "1,/password:/s/password: .+?/password: \"$DB_PASS\"/g" $settings_file
	sed -i -r "1,/host:/s/host: .+?/host: \"$db_host\"/g" $settings_file
	sed -i -r "1,/port:/s/port: .+?/port: 3306/g" $settings_file
}

function create_settings_yaml() {
  local settings_file=$1
  mkdir -p /data/www-provisioned/$(dirname $settings_file)
  if [ ! -f /data/www-provisioned/$settings_file ] ; then
    cp /Settings.yaml /data/www-provisioned/$settings_file
  fi
}

function behat_configure_yml_files() {
  local behat_vhost=$@

  cd /data/www-provisioned

  for f in Packages/*/*/Tests/Behavior/behat.yml.dist; do
    target_file=${f/.dist/}
    if [ ! -f $target_file ]; then
      cp $f $target_file
    fi
    # Find all base_url: setting (might be commented out) and replace it with $behat_vhost
    sed -i -r "s/(#\s?)?base_url:.+/base_url: http:\/\/${behat_vhost}\//g" $target_file
    echo "$target_file configured for Behat testing."
  done
}

# Provision conainer at first run
if [ -f /data/www/composer.json ] || [ -f /data/www-provisioned/composer.json ] || [ -z "$REPOSITORY_URL" -a ! -f "/src/composer.json" ]
then
	echo "Do nothing, initial provisioning done"
	# Update DB Settings to keep them in sync with the docker ENV vars
	update_settings_yaml Configuration/Settings.yaml $DB_HOST
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

    # Apply beard patches
    if [ -f /data/www-provisioned/beard.json ]
        then
            beard patch
    fi

    ###
    # Tweak DB connection settings
    ###
    create_settings_yaml Configuration/Settings.yaml
		update_settings_yaml Configuration/Settings.yaml $DB_HOST

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

# create/update Behat Test Setup
if [ "$DB_TEST_HOST" ] ; then
  for context in Development/Behat Testing/Behat ; do
    create_settings_yaml Configuration/$context/Settings.yaml
    update_settings_yaml Configuration/$context/Settings.yaml $DB_TEST_HOST
  done
  behat_configure_yml_files behat.dev.local:${WWW_PORT}
  chown www-data:www-data -R /data/www-provisioned/Configuration
fi
