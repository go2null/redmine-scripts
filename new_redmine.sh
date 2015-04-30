#!/bin/sh

# script to setup a new redmine installation based on instructions from
#   http://www.redmine.org/projects/redmine/wiki/RedmineInstall

# DEPENDS: git, ruby, mysql|mariadb

# Allow variables to be specified on calling line
[ -z "$REDMINE_PARENT_DIR" ] && REDMINE_PARENT_DIR="$HOME/repos"
[ -z "$REDMINE_DIR" ]        && REDMINE_DIR='redmine'
# Redmine sytem user on the server
[ -z "$REDMINE_USER" ]       && REDMINE_USER="$USER"
[ -z "$REDMINE_GROUP" ]      && REDMINE_GROUP="$USER"
# Redmine database user
[ -z "$REDMINE_DB_USER" ]    && REDMINE_DB_USER='redmine'
# Redmine source
[ -z "$REDMINE_GIT" ]        && REDMINE_GIT='https://github.com/redmine/redmine.git'
# Redmine version (Tag) to checkout.
# REDMINE_VERSION=3.0.0

# init log
LOG_FILE="/tmp/$(echo $0-$REDMINE_PARENT_DIR-$REDMINE_DIR | tr '/' '-' | tr ' ' '-').log"
echo "Installion will be logged to '$LOG_FILE'."

# ensure you are in the parent directory of the new redmine install
mkdir -p "$REDMINE_PARENT_DIR"
if ! cd "$REDMINE_PARENT_DIR"; then
	echo "ERROR: Failed to enter parent directory ('$REDMINE_PARENT_DIR')."
	exit 1
fi

# Step 1 - Redmine application

# clone repo.
# leave git output to act as progress bar.
if git clone "$REDMINE_GIT" "$REDMINE_DIR"; then
	echo "Redmine cloned to '$REDMINE_PARENT_DIR/$REDMINE_DIR'."
else
	echo "ERROR: Failed to clone Redmine from '$REDMINE_GIT' to '$REDMINE_PARENT_DIR/$REDMINE_DIR'."
	exit 1
fi
cd "$REDMINE_DIR"

# checkout version
if [ -z "$REDMINE_VERSION" ]; then
	# checkout new branch of latest release.
	# example: branch == 260 if tag == 2.6.0
	REDMINE_VERSION=$(git tag | tail -n 1)
fi
if ! git checkout "$REDMINE_VERSION" --quiet; then
	echo "WARNING: Failed to checkout specified $REDMINE_VERSION. Checking out latest version."
	REDMINE_VERSION=$(git tag | tail -n 1)
	git checkout "$REDMINE_VERSION" --quiet
fi
BRANCH=$(echo $REDMINE_VERSION | tr -d '.')
if git checkout -b "$BRANCH" >>"$LOG_FILE"; then
	echo "Version '$REDMINE_VERSION' checked out as branch '$BRANCH'"
else
	echo "WARNING: Failed to create development branch '$BRANCH'."
fi

# Step 2 - Create an empty database and accompanying user

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
	echo "Database 'redmine_$BRANCH' created and user '$REDMINE_DB_USER' given full permission."
else
	echo "ERROR: Failed to create database 'redmine_$BRANCH' and user '$REDMINE_DB_USER'."
	exit 1
fi

# Step 3 - Database connection configuration
# on branch $BRANCH
cp config/database.yml.example                      config/database.yml
sed -i "s|\(database: redmine\)$|\1_$BRANCH|"       config/database.yml
sed -i "s|\(username:\) root$|\1 $REDMINE_DB_USER|" config/database.yml
echo "Database configuration ('config/database.yml') created."

# Step 4 - Dependencies installation¶
if which sudo >/dev/null 2>&1; then
	echo "Enter your 'sudo' password if requested:"
	sudo gem install bundler
else
	gem install bundler
fi
if ! bundle install --no-deployment --without development test >>"$LOG_FILE"; then
	echo 'ERROR: Failed to download dependencies.'
	exit 1
fi

# Step 5 - Session store secret generation
if ! bundle exec rake generate_secret_token >>"$LOG_FILE"; then
	echo 'ERROR: Failed to initialize Redmine. [generate_secret_token]'
	exit 1
fi

# Step 6 - Database schema objects creation
if ! RAILS_ENV=production bundle exec rake db:migrate >>"$LOG_FILE"; then
	echo 'ERROR: Failed to initialize Redmine. [db:migrate]'
	exit 1
fi

# Step 7 - Database default data set
if ! RAILS_ENV=production REDMINE_LANG=en bundle exec rake redmine:load_default_data >>"$LOG_FILE"; then
	echo 'ERROR: Failed to initialize Redmine. [redmine:load_default_data]'
	exit 1
fi

# Step 8 - File system permissions
mkdir -p tmp/pdf public/plugin_assets
sudo chown -R $REDMINE_USER:$REDMINE_GROUP files log tmp public/plugin_assets
sudo chmod -R 755 files log tmp public/plugin_assets

echo "Installation of Redmine v$REDMINE_VERSION completed."

# Step 9 - Test the installation
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

