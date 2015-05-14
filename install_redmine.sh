#!/bin/sh

# script to setup a new redmine installation based on instructions from
#   http://www.redmine.org/projects/redmine/wiki/RedmineInstall
# Works for Redmine v2.3.0+.
#	Redmine v2.x before v2.3 seems to have a hard dependency on the PostgreSQL gem (pg),
#	which fails to build if PostgreSQL is not installed.

# DEPENDS: git, ruby, mysql|mariadb
VERSION=0.1.0


# http://unix.stackexchange.com/questions/65803/why-is-printf-better-than-echo
function ECHO() {
  if [ "$#" -gt 0 ]; then
     printf '%s' "$1"
     shift
  fi
  if [ "$#" -gt 0 ]; then
     printf ' %s' "$@"
  fi
  printf '\n'
}


# Allow variables to be specified on calling line
# Redmine source
[ -z "$REDMINE_GIT" ]        && REDMINE_GIT='https://github.com/redmine/redmine.git'
# Redmine version (Tag) to checkout.
#REDMINE_VERSION='3.'
# where to install Redmine
[ -z "$REDMINE_PARENT_DIR" ] && REDMINE_PARENT_DIR="$HOME/repos"
if [ -z "$REDMINE_DIR" ]; then
	if [ -z "$REDMINE_VERSION" ]; then
		REDMINE_DIR='redmine'
	else
		BRANCH=$(printf '%s' "$REDMINE_VERSION" | tr -d '.')
		REDMINE_DIR="redmine_$BRANCH"
	fi
fi
# bundle env variable
[ -z "$RAILS_ENV" ]          && export RAILS_ENV='production'
[ -z "$REDMINE_LANG" ]       && export REDMINE_LANG='en'
# Redmine system user on the server
[ -z "$REDMINE_USER" ]       && REDMINE_USER="$USER"
[ -z "$REDMINE_GROUP" ]      && REDMINE_GROUP="$USER"
# Redmine database user
[ -z "$REDMINE_DB_USER" ]    && REDMINE_DB_USER='redmine'

# internal variables
if [ $(id -u) -eq 0 ]; then
	SUDO=''
elif command -v sudo >/dev/null; then
	SUDO='sudo'
else
	SUDO=''
fi


# init log
LOG_FILE="/tmp/$(printf '%s' "$0-$REDMINE_PARENT_DIR-$REDMINE_DIR" | tr '/' '-' | tr ' ' '-').log"
printf '%s\n' "Installion will be logged to '$LOG_FILE'."
printf '\n'                                            | tee -a "$LOG_FILE"
printf '%s\n' "$(date +"%F %T"): Configuration"      | tee -a "$LOG_FILE"
printf '%s\n' "REDMINE_GIT=$REDMINE_GIT"               | tee -a "$LOG_FILE"
printf '%s\n' "REDMINE_VERSION=$REDMINE_VERSION"       | tee -a "$LOG_FILE"
printf '%s\n' "REDMINE_PARENT_DIR=$REDMINE_PARENT_DIR" | tee -a "$LOG_FILE"
printf '%s\n' "REDMINE_DIR=$REDMINE_DIR"               | tee -a "$LOG_FILE"
printf '%s\n' "REDMINE_USER=$REDMINE_USER"             | tee -a "$LOG_FILE"
printf '%s\n' "REDMINE_GROUP=$REDMINE_GROUP"           | tee -a "$LOG_FILE"
printf '%s\n' "REDMINE_DB_USER=$REDMINE_DB_USER"       | tee -a "$LOG_FILE"


# ensure you are in the parent directory of the new redmine install
mkdir -p "$REDMINE_PARENT_DIR"
if ! cd "$REDMINE_PARENT_DIR"; then
	printf '%s\n' "ERROR: Failed to enter parent directory ('$REDMINE_PARENT_DIR')."
	exit 1
fi


printf '\n%s\n' 'Step 1 - Redmine application'

# clone repo.
# leave git output to act as progress bar.
if git clone "$REDMINE_GIT" "$REDMINE_DIR"; then
	printf '%s\n' "Redmine cloned to '$REDMINE_PARENT_DIR/$REDMINE_DIR'."
else
	printf '%s\n' "ERROR: Failed to clone Redmine from '$REDMINE_GIT' to '$REDMINE_PARENT_DIR/$REDMINE_DIR'."
	exit 1
fi
cd "$REDMINE_DIR"

# checkout version
# allow for versions like '3.' (lastest 3-series) and '3.0' (latest 3.0 series)
[    "$REDMINE_VERSION" ] && REDMINE_VERSION="$(git tag | grep "$REDMINE_VERSION" | tail -n 1)"
# default to latest version
[ -z "$REDMINE_VERSION" ] && REDMINE_VERSION="$(git tag | tail -n 1)"
BRANCH=$(printf '%s' "$REDMINE_VERSION" | tr -d '.')
# checkout
if git checkout -b "$BRANCH" >> "$LOG_FILE"; then
	printf '%s\n' "Version '$REDMINE_VERSION' checked out as branch '$BRANCH'"
else
	printf '%s\n' "ERROR: Failed to create development branch '$BRANCH'."
	exit 1
fi


printf '\n%s\n' 'Step 2 - Create an empty database and accompanying user'

# create database and user (if user doesn't exist)
echo "Enter your MySQL/MariaDB 'root' password:"
if mysql -u root -p -e "
	CHARSET utf8;
	SET NAMES utf8 COLLATE utf8_unicode_ci;
	SET character_set_server = utf8;
	SET collation_server     = utf8_unicode_ci;
	DROP DATABASE IF EXISTS redmine_$BRANCH;
	CREATE DATABASE redmine_$BRANCH DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_unicode_ci;
	GRANT ALL PRIVILEGES ON redmine_$BRANCH.* TO '$REDMINE_DB_USER'@'localhost' IDENTIFIED BY '';
	"
then
	printf '%s\n' "Database 'redmine_$BRANCH' created and user '$REDMINE_DB_USER' given full permission."
else
	printf '%s\n' "ERROR: Failed to create database 'redmine_$BRANCH' and user '$REDMINE_DB_USER'."
	exit 1
fi


printf '\n%s\n' 'Step 3 - Database connection configuration'
# on branch $BRANCH
cp config/database.yml.example                      config/database.yml
sed -i "s|\(database: redmine\)$|\1_$BRANCH|"       config/database.yml
sed -i "s|\(username:\) root$|\1 $REDMINE_DB_USER|" config/database.yml
echo "Database configuration ('config/database.yml') created."


printf '\n%s\n' 'Step 4 - Dependencies installation'
echo "Enter your 'sudo' password if requested:"
if ! $SUDO gem install bundler; then
	echo 'ERROR: Failed to install "bundler". [install bundler]'
	exit 1
fi
if ! bundle install --no-deployment --without development test; then
	echo 'ERROR: Failed to download dependencies. [bundle install].'
	exit 1
fi


printf '\n\n%s\n' 'Step 5 - Session store secret generation'
if ! bundle exec rake generate_secret_token >> "$LOG_FILE"; then
	echo 'ERROR: Failed to initialize Redmine. [generate_secret_token]'
	exit 1
fi


printf '\n\n%s\n' 'Step 6 - Database schema objects creation'
if ! bundle exec rake db:migrate >> "$LOG_FILE"; then
	echo 'ERROR: Failed to initialize Redmine. [db:migrate]'
	exit 1
fi


printf '\n\n%s\n' 'Step 7 - Database default data set'
	if ! bundle exec rake redmine:load_default_data >> "$LOG_FILE"; then
	echo 'ERROR: Failed to initialize Redmine. [redmine:load_default_data]'
	exit 1
fi


printf '\n\n%s\n' 'Step 8 - File system permissions'
mkdir -p tmp/pdf public/plugin_assets
$SUDO chown -R "$REDMINE_USER":"$REDMINE_GROUP" files log tmp public/plugin_assets
$SUDO chmod -R 755 files log tmp public/plugin_assets

printf '\n%s\n' "Installation of Redmine v$REDMINE_VERSION completed."


printf '\n\n%s\n' 'Step 9 - Test the installation'
# open default browser before starying server
#	to allow leaving server in foreground (to allow CTRL+C break)
if which xdg-open >/dev/null 2>&1; then
	xdg-open "$LOG_FILE" &
	xdg-open http://localhost:3000/ &
fi
# test for new location of 'rails' script (Redmine 3.x), falling back to old location.
if [ -e bin/rails ]; then
	bundle exec ruby bin/rails server webrick -e production
else
	bundle exec ruby script/rails server webrick -e production
fi

