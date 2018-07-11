#!/usr/bin/env bash

## Source of the vercomp function: https://stackoverflow.com/questions/4023830/how-to-compare-two-strings-in-dot-separated-version-format-in-bash
##vercomp () {
##    if [[ $1 == $2 ]]
##    then
##        return 0
##    fi
##    local IFS=.
##    local i ver1=($1) ver2=($2)
##    # fill empty fields in ver1 with zeros
##    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
##    do
##        ver1[i]=0
##    done
##    for ((i=0; i<${#ver1[@]}; i++))
##    do
##        if [[ -z ${ver2[i]} ]]
##        then
##            # fill empty fields in ver2 with zeros
##            ver2[i]=0
##        fi
##        if ((10#${ver1[i]} > 10#${ver2[i]}))
##        then
##            return 1
##        fi
##        if ((10#${ver1[i]} < 10#${ver2[i]}))
##        then
##            return 2
##        fi
##    done
##    return 0
##}

MISP_BRANCH='2.4'

# Grub config (reverts network interface names to ethX)
GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"
DEFAULT_GRUB=/etc/default/grub

# Ubuntu version
UBUNTU_VERSION="$(lsb_release -r -s)"

# MISP Configurables
PATH_TO_MISP='/var/www/MISP'
CAKE="${PATH_TO_MISP}/app/Console/cake"
MISP_BASEURL=''
MISP_LIVE='1'

# Database configuration
DBHOST='localhost'
DBNAME='misp'
DBUSER_ADMIN='root'
DBPASSWORD_ADMIN="$(openssl rand -hex 32)"
DBUSER_MISP='misp'
DBPASSWORD_MISP="$(openssl rand -hex 32)"

# Webserver configuration
FQDN='localhost'

# Timing creation
TIME_START=$(date +%s)

# OpenSSL configuration
OPENSSL_C='LU'
OPENSSL_ST='State'
OPENSSL_L='Location'
OPENSSL_O='Organization'
OPENSSL_OU='Organizational Unit'
OPENSSL_CN='Common Name'
OPENSSL_EMAILADDRESS='info@localhost'

# GPG configuration
GPG_REAL_NAME='Autogenerated Key'
GPG_COMMENT='WARNING: MISP AutoGenerated VM consider this Key VOID!'
GPG_EMAIL_ADDRESS='admin@admin.test'
GPG_KEY_LENGTH='2048'
GPG_PASSPHRASE='Password1234'

# php.ini configuration
upload_max_filesize=50M
post_max_size=50M
max_execution_time=300
memory_limit=512M
PHP_INI='/etc/php/7.1/apache2/php.ini'
## Starting Ubuntu 18.04 php71 is default
##vercomp 18.04 ${UBUNTU_VERSION}
##case $? in
##    0) op='=';PHP_INI='/etc/php/7.1/apache2/php.ini';;
##    1) op='>';PHP_INI='/etc/php/7.1/apache2/php.ini';;
##    2) op='<';PHP_INI='/etc/php/7.0/apache2/php.ini';;
##esac


echo "--- Installing MISP… ---"

# echo "--- Configuring GRUB ---"
#
# for key in GRUB_CMDLINE_LINUX
# do
#     sudo sed -i "s/^\($key\)=.*/\1=\"$(eval echo \${$key})\"/" $DEFAULT_GRUB
# done
# sudo grub-mkconfig -o /boot/grub/grub.cfg

echo "--- Updating packages list ---"
sudo apt-get -qq update

echo "--- Upgrading and autoremoving packages ---"
sudo apt-get -y upgrade
sudo apt-get -y autoremove

echo "--- Install base packages ---"
sudo apt-get -y install curl net-tools gcc git gnupg-agent make python openssl redis-server sudo tmux vim virtualenvwrapper zip python3-pythonmagick tesseract-ocr htop imagemagick asciidoctor jq > /dev/null 2>&1


echo "--- Installing and configuring Postfix ---"
# # Postfix Configuration: Satellite system
# # change the relay server later with:
# sudo postconf -e 'relayhost = example.com'
# sudo postfix reload
echo "postfix postfix/mailname string `hostname`.misp.local" | debconf-set-selections
echo "postfix postfix/main_mailer_type string 'Satellite system'" | debconf-set-selections
sudo apt-get install -y postfix > /dev/null 2>&1


echo "--- Installing MariaDB specific packages and settings ---"
sudo apt-get install -y mariadb-client mariadb-server > /dev/null 2>&1
# Secure the MariaDB installation (especially by setting a strong root password)
sleep 10 # give some time to the DB to launch...
sudo systemctl restart mariadb.service
sleep 10
sudo apt-get install -y expect > /dev/null 2>&1
## do we need to spawn mysql_secure_install with sudo in future?
expect -f - <<-EOF
  set timeout 10
  spawn mysql_secure_installation
  expect "Enter current password for root (enter for none):"
  send -- "\r"
  expect "Set root password?"
  send -- "y\r"
  expect "New password:"
  send -- "${DBPASSWORD_ADMIN}\r"
  expect "Re-enter new password:"
  send -- "${DBPASSWORD_ADMIN}\r"
  expect "Remove anonymous users?"
  send -- "y\r"
  expect "Disallow root login remotely?"
  send -- "y\r"
  expect "Remove test database and access to it?"
  send -- "y\r"
  expect "Reload privilege tables now?"
  send -- "y\r"
  expect eof
EOF
sudo apt-get purge -y expect > /dev/null 2>&1


echo "--- Installing Apache2 ---"
sudo apt-get install -y apache2 apache2-doc apache2-utils > /dev/null 2>&1
echo "--- Installing mod-wsgi-py3 for misp-dashboard ---"
sudo apt-get install -y libapache2-mod-wsgi-py3 > /dev/null 2>&1
sudo a2dismod status > /dev/null 2>&1
sudo a2enmod ssl > /dev/null 2>&1
sudo a2enmod rewrite > /dev/null 2>&1
sudo a2dissite 000-default > /dev/null 2>&1
sudo a2ensite default-ssl > /dev/null 2>&1


echo "--- Installing PHP-specific packages ---"
sudo apt-get install -y libapache2-mod-php php php-cli php-crypt-gpg php-dev php-json php-mysql php-opcache php-readline php-redis php-xml > /dev/null 2>&1

echo "--- Configuring PHP ---"
for key in upload_max_filesize post_max_size max_execution_time max_input_time memory_limit
do
 sudo sed -i "s/^\($key\).*/\1 = $(eval echo \${$key})/" $PHP_INI
done

echo "--- Restarting Apache ---"
sudo systemctl restart apache2 > /dev/null 2>&1


echo "--- Retrieving MISP ---"
## Double check perms.
sudo mkdir $PATH_TO_MISP
sudo chown www-data:www-data $PATH_TO_MISP
cd $PATH_TO_MISP
sudo -u www-data git clone -b $MISP_BRANCH https://github.com/MISP/MISP.git $PATH_TO_MISP
#git checkout tags/$(git describe --tags `git rev-list --tags --max-count=1`)
sudo -u www-data git config core.filemode false
# chown -R www-data $PATH_TO_MISP
# chgrp -R www-data $PATH_TO_MISP
# chmod -R 700 $PATH_TO_MISP


echo "--- Installing Mitre's STIX ---"
sudo apt-get install -y python-dev python3-dev python-pip python3-pip libxml2-dev libxslt1-dev zlib1g-dev python-setuptools > /dev/null 2>&1
cd $PATH_TO_MISP/app/files/scripts
sudo -u www-data git clone https://github.com/CybOXProject/python-cybox.git
sudo -u www-data git clone https://github.com/STIXProject/python-stix.git
cd $PATH_TO_MISP/app/files/scripts/python-cybox
sudo python3 setup.py install > /dev/null 2>&1
cd $PATH_TO_MISP/app/files/scripts/python-stix
sudo python3 setup.py install > /dev/null 2>&1
# install mixbox to accomodate the new STIX dependencies:
cd $PATH_TO_MISP/app/files/scripts/
sudo -u www-data git clone https://github.com/CybOXProject/mixbox.git
cd $PATH_TO_MISP/app/files/scripts/mixbox
sudo python3 setup.py install > /dev/null 2>&1

echo "--- Installing misp-dashboard ---"
cd /var/www
sudo mkdir misp-dashboard
sudo chown www-data:www-data misp-dashboard
sudo -u www-data git clone https://github.com/MISP/misp-dashboard.git
cd misp-dashboard
sudo /var/www/misp-dashboard/install_dependencies.sh
sudo sed -i "s/^host\ =\ localhost/host\ =\ 0.0.0.0/g" /var/www/misp-dashboard/config/config.cfg

echo "--- Retrieving CakePHP… ---"
# CakePHP is included as a submodule of MISP, execute the following commands to let git fetch it:
cd $PATH_TO_MISP
sudo -u www-data git submodule init
sudo -u www-data git submodule update
# Once done, install CakeResque along with its dependencies if you intend to use the built in background jobs:
# Make composer cache happy
mkdir /var/www/.composer ; chown www-data:www-data /var/www/.composer
cd $PATH_TO_MISP/app
sudo -u www-data php composer.phar require kamisama/cake-resque:4.1.2
sudo -u www-data php composer.phar config vendor-dir Vendor
sudo -u www-data php composer.phar install
# Enable CakeResque with php-redis
sudo phpenmod redis
# To use the scheduler worker for scheduled tasks, do the following:
sudo -u www-data cp -fa $PATH_TO_MISP/INSTALL/setup/config.php $PATH_TO_MISP/app/Plugin/CakeResque/Config/config.php


echo "--- Setting the permissions… ---"
sudo chown -R www-data:www-data $PATH_TO_MISP
sudo chmod -R 750 $PATH_TO_MISP
sudo chmod -R g+ws $PATH_TO_MISP/app/tmp
sudo chmod -R g+ws $PATH_TO_MISP/app/files
sudo chmod -R g+ws $PATH_TO_MISP/app/files/scripts/tmp


echo "--- Creating a database user… ---"
sudo mysql -u $DBUSER_ADMIN -p$DBPASSWORD_ADMIN -e "create database $DBNAME;"
sudo mysql -u $DBUSER_ADMIN -p$DBPASSWORD_ADMIN -e "grant usage on *.* to $DBNAME@localhost identified by '$DBPASSWORD_MISP';"
sudo mysql -u $DBUSER_ADMIN -p$DBPASSWORD_ADMIN -e "grant all privileges on $DBNAME.* to '$DBUSER_MISP'@'localhost';"
sudo mysql -u $DBUSER_ADMIN -p$DBPASSWORD_ADMIN -e "flush privileges;"
# Import the empty MISP database from MYSQL.sql
sudo -u www-data cat /var/www/MISP/INSTALL/MYSQL.sql | mysql -u $DBUSER_MISP -p$DBPASSWORD_MISP $DBNAME


echo "--- Configuring Apache… ---"
# !!! apache.24.misp.ssl seems to be missing
#cp $PATH_TO_MISP/INSTALL/apache.24.misp.ssl /etc/apache2/sites-available/misp-ssl.conf
# If a valid SSL certificate is not already created for the server, create a self-signed certificate:
sudo openssl req -newkey rsa:4096 -days 365 -nodes -x509 -subj "/C=$OPENSSL_C/ST=$OPENSSL_ST/L=$OPENSSL_L/O=<$OPENSSL_O/OU=$OPENSSL_OU/CN=$OPENSSL_CN/emailAddress=$OPENSSL_EMAILADDRESS" -keyout /etc/ssl/private/misp.local.key -out /etc/ssl/private/misp.local.crt > /dev/null


echo "--- Adding Listen 8001 for misp-dashboard ---"
sudo sed -i '/Listen 80/a Listen 0.0.0.0:8001' /etc/apache2/ports.conf

echo "--- Add a VirtualHost for MISP and misp-dashboard ---"
## Again double check this perm madness ;)
sudo cat > /etc/apache2/sites-available/misp-ssl.conf <<EOF
<VirtualHost *:80>
    ServerAdmin admin@misp.local
    ServerName misp.local
    DocumentRoot $PATH_TO_MISP/app/webroot

    <Directory $PATH_TO_MISP/app/webroot>
        Options -Indexes
        AllowOverride all
        Require all granted
    </Directory>

    LogLevel warn
    ErrorLog /var/log/apache2/misp.local_error.log
    CustomLog /var/log/apache2/misp.local_access.log combined
    ServerSignature Off
</VirtualHost>
EOF

sudo cat > /etc/apache2/sites-available/misp-dashboard.conf <<EOF
<VirtualHost *:8001>
    ServerAdmin admin@misp.local
    ServerName misp.local

    DocumentRoot /var/www/misp-dashboard
    
    WSGIDaemonProcess misp-dashboard \
       user=misp group=misp \
       python-home=/var/www/misp-dashboard/DASHENV \
       processes=1 \
       threads=15 \
       maximum-requests=5000 \
       listen-backlog=100 \
       queue-timeout=45 \
       socket-timeout=60 \
       connect-timeout=15 \
       request-timeout=60 \
       inactivity-timeout=0 \
       deadlock-timeout=60 \
       graceful-timeout=15 \
       eviction-timeout=0 \
       shutdown-timeout=5 \
       send-buffer-size=0 \
       receive-buffer-size=0 \
       header-buffer-size=0 \
       response-buffer-size=0 \
       server-metrics=Off

    WSGIScriptAlias / /var/www/misp-dashboard/misp-dashboard.wsgi

    <Directory /var/www/misp-dashboard>
        WSGIProcessGroup misp-dashboard
        WSGIApplicationGroup %{GLOBAL}
        Require all granted
    </Directory>

    LogLevel info
    ErrorLog /var/log/apache2/misp-dashboard.local_error.log
    CustomLog /var/log/apache2/misp-dashboard.local_access.log combined
    ServerSignature Off
</VirtualHost>
EOF

# cat > /etc/apache2/sites-available/misp-ssl.conf <<EOF
# <VirtualHost *:80>
#         ServerName misp.local
#
#         Redirect permanent / https://$FQDN
#
#         LogLevel warn
#         ErrorLog /var/log/apache2/misp.local_error.log
#         CustomLog /var/log/apache2/misp.local_access.log combined
#         ServerSignature Off
# </VirtualHost>
#
# <VirtualHost *:443>
#         ServerAdmin me@me.local
#         ServerName misp.local
#         DocumentRoot $PATH_TO_MISP/app/webroot
#
#         <Directory $PATH_TO_MISP/app/webroot>
#             Options -Indexes
#             AllowOverride all
#             Require all granted
#         </Directory>
#
#         SSLEngine On
#         SSLCertificateFile /etc/ssl/private/misp.local.crt
#         SSLCertificateKeyFile /etc/ssl/private/misp.local.key
#         #SSLCertificateChainFile /etc/ssl/private/misp-chain.crt
#
#         LogLevel warn
#         ErrorLog /var/log/apache2/misp.local_error.log
#         CustomLog /var/log/apache2/misp.local_access.log combined
#         ServerSignature Off
# </VirtualHost>
# EOF
# activate new vhost
sudo a2dissite default-ssl
sudo a2ensite misp-ssl
sudo a2ensite misp-dashboard


echo "--- Restarting Apache ---"
sudo systemctl restart apache2 > /dev/null 2>&1


echo "--- Configuring log rotation ---"
sudo cp $PATH_TO_MISP/INSTALL/misp.logrotate /etc/logrotate.d/misp


echo "--- MISP configuration ---"
# There are 4 sample configuration files in /var/www/MISP/app/Config that need to be copied
sudo -u www-data cp -a $PATH_TO_MISP/app/Config/bootstrap.default.php /var/www/MISP/app/Config/bootstrap.php
sudo -u www-data cp -a $PATH_TO_MISP/app/Config/database.default.php /var/www/MISP/app/Config/database.php
sudo -u www-data cp -a $PATH_TO_MISP/app/Config/core.default.php /var/www/MISP/app/Config/core.php
sudo -u www-data cp -a $PATH_TO_MISP/app/Config/config.default.php /var/www/MISP/app/Config/config.php
sudo -u www-data cat > $PATH_TO_MISP/app/Config/database.php <<EOF
<?php
class DATABASE_CONFIG {
        public \$default = array(
                'datasource' => 'Database/Mysql',
                //'datasource' => 'Database/Postgres',
                'persistent' => false,
                'host' => '$DBHOST',
                'login' => '$DBUSER_MISP',
                'port' => 3306, // MySQL & MariaDB
                //'port' => 5432, // PostgreSQL
                'password' => '$DBPASSWORD_MISP',
                'database' => '$DBNAME',
                'prefix' => '',
                'encoding' => 'utf8',
        );
}
EOF
# and make sure the file permissions are still OK
sudo chown -R www-data:www-data $PATH_TO_MISP/app/Config
sudo chmod -R 750 $PATH_TO_MISP/app/Config
# Set some MISP directives with the command line tool
$CAKE Live $MISP_LIVE

# Enable ZeroMQ
$CAKE Admin setSetting "Plugin.ZeroMQ_enable" true
$CAKE Admin setSetting "Plugin.ZeroMQ_event_notifications_enable" true
$CAKE Admin setSetting "Plugin.ZeroMQ_object_notifications_enable" true
$CAKE Admin setSetting "Plugin.ZeroMQ_object_reference_notifications_enable" true
$CAKE Admin setSetting "Plugin.ZeroMQ_attribute_notifications_enable" true
$CAKE Admin setSetting "Plugin.ZeroMQ_sighting_notifications_enable" true
$CAKE Admin setSetting "Plugin.ZeroMQ_user_notifications_enable" true
$CAKE Admin setSetting "Plugin.ZeroMQ_organisation_notifications_enable" true
$CAKE Admin setSetting "Plugin.ZeroMQ_port" 50000
$CAKE Admin setSetting "Plugin.ZeroMQ_redis_host" "localhost"
$CAKE Admin setSetting "Plugin.ZeroMQ_redis_port" 6379
$CAKE Admin setSetting "Plugin.ZeroMQ_redis_database" 1
$CAKE Admin setSetting "Plugin.ZeroMQ_redis_namespace" "mispq"
$CAKE Admin setSetting "Plugin.ZeroMQ_include_attachments" false
$CAKE Admin setSetting "Plugin.ZeroMQ_tag_notifications_enable" false
$CAKE Admin setSetting "Plugin.ZeroMQ_audit_notifications_enable" false

# Enable GnuPG
$CAKE Admin setSetting "GnuPG.email" "admin@admin.test"
$CAKE Admin setSetting "GnuPG.homedir" "/var/www/MISP/.gnupg"
$CAKE Admin setSetting "GnuPG.password" "Password1234"

# Enable Enrichment set better timeouts
$CAKE Admin setSetting "Plugin.Enrichment_services_enable" true
$CAKE Admin setSetting "Plugin.Enrichment_hover_enable" true
$CAKE Admin setSetting "Plugin.Enrichment_timeout" 300
$CAKE Admin setSetting "Plugin.Enrichment_hover_timeout" 150
$CAKE Admin setSetting "Plugin.Enrichment_cve_enabled" true
$CAKE Admin setSetting "Plugin.Enrichment_dns_enabled" true
$CAKE Admin setSetting "Plugin.Enrichment_services_url" "http://127.0.0.1"
$CAKE Admin setSetting "Plugin.Enrichment_services_port" 6666

# Enable Import modules set better timout
$CAKE Admin setSetting "Plugin.Import_services_enable" true
$CAKE Admin setSetting "Plugin.Import_services_url" "http://127.0.0.1"
$CAKE Admin setSetting "Plugin.Import_services_port" 6666
$CAKE Admin setSetting "Plugin.Import_timeout" 300
$CAKE Admin setSetting "Plugin.Import_ocr_enabled" true
$CAKE Admin setSetting "Plugin.Import_csvimport_enabled" true

# Enable Export modules set better timout
$CAKE Admin setSetting "Plugin.Export_services_enable" true
$CAKE Admin setSetting "Plugin.Export_services_url" "http://127.0.0.1"
$CAKE Admin setSetting "Plugin.Export_services_port" 6666
$CAKE Admin setSetting "Plugin.Export_timeout" 300
$CAKE Admin setSetting "Plugin.Export_pdfexport_enabled" true

# Enable installer org and tune some configurables
$CAKE Admin setSetting "MISP.host_org_id" 1
$CAKE Admin setSetting "MISP.email" "info@admin.test"
$CAKE Admin setSetting "MISP.disable_emailing" true
$CAKE Admin setSetting "MISP.contact" "info@admin.test"
$CAKE Admin setSetting "MISP.disablerestalert" true
$CAKE Admin setSetting "MISP.showCorrelationsOnIndex" true

# Provisional Cortex tunes
$CAKE Admin setSetting "Plugin.Cortex_services_enable" false
$CAKE Admin setSetting "Plugin.Cortex_services_url" "http://127.0.0.1"
$CAKE Admin setSetting "Plugin.Cortex_services_port" 9000
$CAKE Admin setSetting "Plugin.Cortex_timeout" 120
$CAKE Admin setSetting "Plugin.Cortex_services_url" "http://127.0.0.1"
$CAKE Admin setSetting "Plugin.Cortex_services_port" 9000
$CAKE Admin setSetting "Plugin.Cortex_services_timeout" 120
$CAKE Admin setSetting "Plugin.Cortex_services_authkey" ""
$CAKE Admin setSetting "Plugin.Cortex_ssl_verify_peer" false
$CAKE Admin setSetting "Plugin.Cortex_ssl_verify_host" false
$CAKE Admin setSetting "Plugin.Cortex_ssl_allow_self_signed" true

# Various plugin sightings settings
$CAKE Admin setSetting "Plugin.Sightings_policy" 0
$CAKE Admin setSetting "Plugin.Sightings_anonymise" false
$CAKE Admin setSetting "Plugin.Sightings_range" 365

# Plugin CustomAuth tuneable
$CAKE Admin setSetting "Plugin.CustomAuth_disable_logout" false

# RPZ Plugin settings

$CAKE Admin setSetting "Plugin.RPZ_policy" "DROP"
$CAKE Admin setSetting "Plugin.RPZ_walled_garden" "127.0.0.1"
$CAKE Admin setSetting "Plugin.RPZ_serial" "\$date00"
$CAKE Admin setSetting "Plugin.RPZ_refresh" "2h"
$CAKE Admin setSetting "Plugin.RPZ_retry" "30m"
$CAKE Admin setSetting "Plugin.RPZ_expiry" "30d"
$CAKE Admin setSetting "Plugin.RPZ_minimum_ttl" "1h"
$CAKE Admin setSetting "Plugin.RPZ_ttl" "1w"
$CAKE Admin setSetting "Plugin.RPZ_ns" "localhost."
$CAKE Admin setSetting "Plugin.RPZ_ns_alt" ""
$CAKE Admin setSetting "Plugin.RPZ_email" "root.localhost"

# Force defaults to make MISP Server Settings less RED
$CAKE Admin setSetting "MISP.language" "eng"
$CAKE Admin setSetting "MISP.proposals_block_attributes" false
## Redis block
$CAKE Admin setSetting "MISP.redis_host" "127.0.0.1"
$CAKE Admin setSetting "MISP.redis_port" 6379
$CAKE Admin setSetting "MISP.redis_database" 13
$CAKE Admin setSetting "MISP.redis_password" ""

# Force defaults to make MISP Server Settings less YELLOW
$CAKE Admin setSetting "MISP.ssdeep_correlation_threshold" 40
$CAKE Admin setSetting "MISP.extended_alert_subject" false
$CAKE Admin setSetting "MISP.default_event_threat_level" 4
$CAKE Admin setSetting "MISP.newUserText" "Dear new MISP user,\\n\\nWe would hereby like to welcome you to the \$org MISP community.\\n\\n Use the credentials below to log into MISP at \$misp, where you will be prompted to manually change your password to something of your own choice.\\n\\nUsername: \$username\\nPassword: \$password\\n\\nIf you have any questions, don't hesitate to contact us at: \$contact.\\n\\nBest regards,\\nYour \$org MISP support team"
$CAKE Admin setSetting "MISP.passwordResetText" "Dear MISP user,\\n\\nA password reset has been triggered for your account. Use the below provided temporary password to log into MISP at \$misp, where you will be prompted to manually change your password to something of your own choice.\\n\\nUsername: \$username\\nYour temporary password: \$password\\n\\nIf you have any questions, don't hesitate to contact us at: \$contact.\\n\\nBest regards,\\nYour \$org MISP support team"
$CAKE Admin setSetting "MISP.enableEventBlacklisting" true
$CAKE Admin setSetting "MISP.enableOrgBlacklisting" true
$CAKE Admin setSetting "MISP.log_client_ip" false
$CAKE Admin setSetting "MISP.log_auth" false
$CAKE Admin setSetting "MISP.disableUserSelfManagement" false
$CAKE Admin setSetting "MISP.block_event_alert" false
$CAKE Admin setSetting "MISP.block_event_alert_tag" "no-alerts=\"true\""
$CAKE Admin setSetting "MISP.block_old_event_alert" false
$CAKE Admin setSetting "MISP.block_old_event_alert_age" ""
$CAKE Admin setSetting "MISP.incoming_tags_disabled_by_default" false
$CAKE Admin setSetting "MISP.footermidleft" "This is an autogenerated VM"
$CAKE Admin setSetting "MISP.footermidright" "Please configure accordingly and do not use in production. 3fb8269"
$CAKE Admin setSetting "MISP.welcome_text_top" "Autogenerated VM"
$CAKE Admin setSetting "MISP.welcome_text_bottom" "Use for testing purposes only, production-use considered harmful."


# Force defaults to make MISP Server Settings less GREEN
$CAKE Admin setSetting "Security.password_policy_length" 12
# $CAKE Admin setSetting "Security.password_policy_complexity" "/^((?=.*\d)|(?=.*\W+))(?![\n])(?=.*[A-Z])(?=.*[a-z]).*$|.{16,}/"

# Tune global time outs
$CAKE Admin setSetting "Session.autoRegenerate" 0
$CAKE Admin setSetting "Session.timeout" 600
$CAKE Admin setSetting "Session.cookie_timeout" 3600

echo "--- Generating a GPG encryption key… ---"
sudo apt-get install -y rng-tools haveged
sudo -u www-data mkdir $PATH_TO_MISP/.gnupg
sudo chmod 700 $PATH_TO_MISP/.gnupg
cat >/tmp/gen-key-script <<EOF
    %echo Generating a default key
    Key-Type: default
    Key-Length: $GPG_KEY_LENGTH
    Subkey-Type: default
    Name-Real: $GPG_REAL_NAME
    Name-Comment: $GPG_COMMENT
    Name-Email: $GPG_EMAIL_ADDRESS
    Expire-Date: 0
    Passphrase: $GPG_PASSPHRASE
    # Do a commit here, so that we can later print "done"
    %commit
    %echo done
EOF
sudo -u www-data gpg --homedir $PATH_TO_MISP/.gnupg --batch --gen-key /tmp/gen-key-script
rm /tmp/gen-key-script
# And export the public key to the webroot
sudo -u www-data sh -c "gpg --homedir $PATH_TO_MISP/.gnupg --export --armor $GPG_EMAIL_ADDRESS > $PATH_TO_MISP/app/webroot/gpg.asc"

echo "--- Making the background workers start on boot… ---"
sudo chmod 755 $PATH_TO_MISP/app/Console/worker/start.sh
# With systemd:
# sudo cat > /etc/systemd/system/workers.service  <<EOF
# [Unit]
# Description=Start the background workers at boot
#
# [Service]
# Type=forking
# User=www-data
# ExecStart=$PATH_TO_MISP/app/Console/worker/start.sh
#
# [Install]
# WantedBy=multi-user.target
# EOF
# sudo systemctl enable workers.service > /dev/null
# sudo systemctl restart workers.service > /dev/null

# With initd:
if [ ! -e /etc/rc.local ]
then
    echo '#!/bin/sh -e' | sudo tee -a /etc/rc.local
    echo 'exit 0' | sudo tee -a /etc/rc.local
    chmod u+x /etc/rc.local
fi


# redis-server requires the following /sys/kernel tweak
sed -i -e '$i \echo never > /sys/kernel/mm/transparent_hugepage/enabled\n' /etc/rc.local
sed -i -e '$i \echo 1024 > /proc/sys/net/core/somaxconn\n' /etc/rc.local
sed -i -e '$i \sysctl vm.overcommit_memory=1\n' /etc/rc.local
sed -i -e '$i \sudo -u www-data bash /var/www/MISP/app/Console/worker/start.sh\n' /etc/rc.local
sed -i -e '$i \sudo -u www-data misp-modules -l 0.0.0.0 -s &\n' /etc/rc.local
sed -i -e '$i \sudo -u www-data bash /var/www/misp-dashboard/start_all.sh\n' /etc/rc.local
sed -i -e '$i \sudo -u misp /usr/local/src/viper/viper-web -p 8888 -H 0.0.0.0 &\n' /etc/rc.local
sed -i -e '$i \git_dirs="/usr/local/src/misp-modules/ /var/www/misp-dashboard /usr/local/src/faup /usr/local/src/mail_to_misp /usr/local/src/misp-modules /usr/local/src/viper /var/www/misp-dashboard"\n' /etc/rc.local
sed -i -e '$i \for d in $git_dirs; do\n' /etc/rc.local
sed -i -e '$i \    echo "Updating ${d}"\n' /etc/rc.local
sed -i -e '$i \    cd $d && sudo git pull &\n' /etc/rc.local
sed -i -e '$i \done\n' /etc/rc.local


echo "--- Installing MISP modules… ---"
mkdir /home/misp/.cache/
sudo apt-get install -y libpq5 libjpeg-dev libfuzzy-dev > /dev/null 2>&1
cd /usr/local/src/
sudo git clone https://github.com/MISP/misp-modules.git
cd misp-modules
# pip3 install
sudo pip3 install -I -r REQUIREMENTS > /dev/null 2>&1
sudo pip3 install -I . > /dev/null 2>&1
sudo pip3 install lief 2>&1
sudo pip3 install maec 2>&1
sudo pip2 install pathlib 2>&1
sudo pip3 install pathlib 2>&1
sudo pip3 install pymisp python-magic wand yara > /dev/null 2>&1
sudo pip3 install git+https://github.com/kbandla/pydeep.git > /dev/null 2>&1
# pip2 install
sudo pip2 install pymisp python-magic wand yara > /dev/null 2>&1
sudo pip2 install git+https://github.com/kbandla/pydeep.git > /dev/null 2>&1
sudo pip2 install lief 2>&1
# install STIX2.0 library to support STIX 2.0 export:
sudo pip3 install stix2 > /dev/null 2>&1
# With systemd:
# sudo cat > /etc/systemd/system/misp-modules.service  <<EOF
# [Unit]
# Description=Start the misp modules server at boot
#
# [Service]
# Type=forking
# User=www-data
# ExecStart=/bin/sh -c 'misp-modules -l 0.0.0.0 -s &'
#
# [Install]
# WantedBy=multi-user.target
# EOF
# sudo systemctl enable misp-modules.service > /dev/null
# sudo systemctl restart misp-modules.service > /dev/null

# With initd:
# sudo sed -i -e '$i \sudo -u www-data misp-modules -l 0.0.0.0 -s &\n' /etc/rc.local

echo "--- Installing viper-framework ---"
cd /usr/local/src/
apt-get install -y libssl-dev swig python3-ssdeep p7zip-full unrar sqlite python3-pyclamd exiftool radare2
pip3 install SQLAlchemy PrettyTable python-magic 2>&1
git clone https://github.com/viper-framework/viper.git
cd viper
git submodule init
git submodule update
pip3 install -r requirements.txt > /dev/null 2>&1
sudo -u misp /usr/local/src/viper/viper-cli -h > /dev/null 2>&1
sudo -u misp /usr/local/src/viper/viper-web -p 8888 -H 0.0.0.0 &
echo 'PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/usr/local/src/viper"' |sudo tee /etc/environment

echo "--- Installing mail2misp ---"
cd /usr/local/src/
sudo apt-get install -y cmake
sudo git clone https://github.com/MISP/mail_to_misp.git
sudo git clone git://github.com/stricaud/faup.git
cd faup
sudo mkdir -p build
cd build
sudo cmake .. && sudo make
sudo make install
sudo ldconfig
cd ../../
cd mail_to_misp
sudo pip3 install -r requirements.txt > /dev/null 2>&1
sudo cp mail_to_misp_config.py-example mail_to_misp_config.py

echo "--- Generating Certificate ---"
sudo openssl req -newkey rsa:4096 -days 3650 -nodes -x509 -subj "/C=LU/ST=/L=Luxembourg/O=CIRCL/OU=VM AutoGen/CN=localhost/emailAddress=admin@admin.test" -keyout /etc/ssl/private/misp.local.key -out /etc/ssl/private/misp.local.crt


echo "--- Setting the permissions… ---"
sudo chown -R www-data:www-data $PATH_TO_MISP
sudo chmod -R 750 $PATH_TO_MISP
sudo chmod -R g+ws $PATH_TO_MISP/app/tmp
sudo chmod -R g+ws $PATH_TO_MISP/app/files
sudo chmod -R g+ws $PATH_TO_MISP/app/files/scripts/tmp

echo "--- Restarting Apache… ---"
sudo systemctl restart apache2 > /dev/null 2>&1
sleep 5

echo "--- Updating the galaxies… ---"
sudo -E $PATH_TO_MISP/app/Console/cake userInit -q > /dev/null
AUTH_KEY=$(mysql -u $DBUSER_MISP -p$DBPASSWORD_MISP misp -e "SELECT authkey FROM users;" | tail -1)
echo "--- Updating the galaxies… ---"
curl --header "Authorization: $AUTH_KEY" --header "Accept: application/json" --header "Content-Type: application/json" -o /dev/null -s -X POST http://127.0.0.1/galaxies/update

echo "--- Updating the taxonomies… ---"
curl --header "Authorization: $AUTH_KEY" --header "Accept: application/json" --header "Content-Type: application/json" -o /dev/null -s -X POST http://127.0.0.1/taxonomies/update

echo "--- Updating the warning lists… ---"
curl --header "Authorization: $AUTH_KEY" --header "Accept: application/json" --header "Content-Type: application/json" -o /dev/null -s -X POST http://127.0.0.1/warninglists/update

echo "--- Updating the notice lists… ---"
curl --header "Authorization: $AUTH_KEY" --header "Accept: application/json" --header "Content-Type: application/json" -o /dev/null -s -X POST http://127.0.0.1/noticelists/update

echo "--- Updating the object templates… ---"
curl --header "Authorization: $AUTH_KEY" --header "Accept: application/json" --header "Content-Type: application/json" -o /dev/null -s -X POST http://127.0.0.1/objectTemplates/update

echo "--- Setting Baseurl ---"
$CAKE Baseurl ""

echo "--- Enabling MISP new pub/sub feature (ZeroMQ)… ---"
sudo apt-get install -y pkg-config python-redis python-zmq python3-zmq > /dev/null 2>&1

echo "--- Configuring viper ---"
sed -i "s/^misp_url\ =/misp_url\ =\ http:\/\/localhost/g" ~/.viper/viper.conf
sed -i "s/^misp_key\ =/misp_key\ =\ $AUTH_KEY/g" ~/.viper/viper.conf
# Setting viper-web admin user password to 'Password1234'
sqlite3 ~/.viper/admin.db 'UPDATE auth_user SET password="pbkdf2_sha256$100000$iXgEJh8hz7Cf$vfdDAwLX8tko1t0M1TLTtGlxERkNnltUnMhbv56wK/U="'

echo "--- Configuring mail2misp ---"
sudo sed -i "s/^misp_url\ =\ 'YOUR_MISP_URL'/misp_url\ =\ 'http:\/\/localhost'/g" /usr/local/src/mail_to_misp/mail_to_misp_config.py
sudo sed -i "s/^misp_key\ =\ 'YOUR_KEY_HERE'/misp_key\ =\ '$AUTH_KEY'/g" /usr/local/src/mail_to_misp/mail_to_misp_config.py

echo "--- Installing asciidoctor-pdf ---"
gem install asciidoctor-pdf --pre
gem install pygments.rb

echo "--- Setting the permissions… ---"
sudo chown -R www-data:www-data $PATH_TO_MISP
sudo chmod -R 750 $PATH_TO_MISP
sudo chmod -R g+ws $PATH_TO_MISP/app/tmp
sudo chmod -R g+ws $PATH_TO_MISP/app/files
sudo chmod -R g+ws $PATH_TO_MISP/app/files/scripts/tmp
sudo chmod 700 $PATH_TO_MISP/.gnupg
sudo chown -R misp:misp ~misp/.viper

echo "--- Ignoring filemode on all submodules ---"
cd $PATH_TO_MISP
git submodule foreach --recursive git config core.filemode false

echo "--- autoremove for apt ---"
apt-get autoremove

echo "--- Setting Baseurl and making sure Sessions do NOT auto regenerate ---"
$CAKE Baseurl ""
$CAKE Admin setSetting "Session.autoRegenerate" 0

echo "\e[32mMISP is ready\e[0m"
echo "Login and passwords for the MISP image are the following:"
echo "Web interface (default network settings): $MISP_BASEURL"
echo "MISP admin:  admin@admin.test/admin"
echo "Shell/SSH: misp/Password1234"
echo "MySQL:  $DBUSER_ADMIN/$DBPASSWORD_ADMIN - $DBUSER_MISP/$DBPASSWORD_MISP"
echo "MySQL:  $DBUSER_ADMIN/$DBPASSWORD_ADMIN - $DBUSER_MISP/$DBPASSWORD_MISP" > ~/mysql.txt
chown misp:misp ~/mysql.txt


TIME_END=$(date +%s)
TIME_DELTA=$(expr ${TIME_END} - ${TIME_START})

echo "The generation took ${TIME_DELTA} seconds"
