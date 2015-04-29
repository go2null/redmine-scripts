# script to setup a new redmine installation based on instructions from
#   http://www.redmine.org/projects/redmine/wiki/RedmineInstall

# DEPENDS: git, mysql|mariadb

# Allow variables to be specified on calling line
[ -z $REDMINE_PARENT_DIR ] && REDMINE_PARENT_DIR="$HOME/repos"
[ -z $REDMINE_DIR ]        && REDMINE_DIR='redmine'
# redmine user on the server
[ -z $REDMINE_USER ]       && REDMINE_USER=$USER
[ -z $REDMINE_GROUP ]      && REDMINE_GROUP=$USER

# ensure you are in the parent directory of the new redmine install
mkdir -p $REDMINE_PARENT_DIR
pushd $REDMINE_PARENT_DIR

# Step 1 - Redmine application

# clone repo
git clone https://github.com/redmine/redmine.git "$REDMINE_DIR"
cd "$REDMINE_DIR"
echo "Redmine cloned to '$REDMINE_PARENT_DIR/$REDMINE_DIR'"

# checkout new branch of latest release
# if tag = 2.6.0, branch = 260
TAG=$(git tag | tail -n 1)
git checkout $TAG
BRANCH=$(echo $TAG | tr -d '.')
git checkout -b $BRANCH
echo "Version '$TAG' checked out to branch '$BRANCH'"

# Step 2 - Create an empty database and accompanying user

# create database and user (if user doesn't exist)
echo "Enter your MySQL/MariaDB 'root' password:"
mysql -u root -p -e "
	CHARSET utf8;
	SET NAMES utf8 COLLATE utf8_unicode_ci;
	SET character_set_server = utf8;
	SET collation_server     = utf8_unicode_ci;
  DROP DATABASE IF EXISTS redmine_$BRANCH;
  CREATE DATABASE redmine_$BRANCH DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_unicode_ci;
  GRANT ALL PRIVILEGES ON redmine_$BRANCH.* TO 'redmine'@'localhost' IDENTIFIED BY '';
"
echo "Database 'redmine_$BRANCH' created and user 'redmine' given full permission."

# Step 3 - Database connection configuration
# on branch $LATEST
cp config/database.yml.example config/database.yml
# update database name
sed -i "s|\(database: redmine\)$|\1_$BRANCH|" config/database.yml
echo "database.yml updated."

# Step 4 - Dependencies installation¶
if which sudo >/dev/null 2>&1; then
	echo "Enter your 'sudo' password if requested:"
 sudo	gem install bundler
else
	gem install bundler
fi
bundle install --no-deployment --without development test

# Step 5 - Session store secret generation
bundle exec rake generate_secret_token

# Step 6 - Database schema objects creation
RAILS_ENV=production                 bundle exec rake db:migrate

# Step 7 - Database default data set
RAILS_ENV=production REDMINE_LANG=en bundle exec rake redmine:load_default_data

# Step 8 - File system permissions
mkdir -p tmp/pdf public/plugin_assets
sudo chown -R $REDMINE_USER:$REDMINE_GROUP files log tmp public/plugin_assets
sudo chmod -R 755 files log tmp public/plugin_assets

# Step 9 - Test the installation
# open default browser before starying server
#	to allow leaving server in foreground (to allow CTRL+C break)
if which xdg-open >/dev/null 2>&1; then
	xdg-open http://localhost:3000/ &
fi
# test for new location of 'rails' script (Redmine 3.0), falling back to old location.
if [ -e bin/rails ]; then
	bundle exec ruby bin/rails server webrick -e production
else
	bundle exec ruby script/rails server webrick -e production
fi
# cleanup
popd
