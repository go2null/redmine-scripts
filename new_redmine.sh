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
mkdir $REDMINE_PARENT_DIR
cd $REDMINE_PARENT_DIR

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
  DROP DATABASE IF EXISTS redmine_$BRANCH;
  CREATE DATABASE redmine_$BRANCH CHARACTER SET utf8;
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
echo "Enter your 'sudo' password if requested:"
sudo gem install bundler
bundle install --no-deployment --without development test

# Step 5 - Session store secret generation
bundle exec rake generate_secret_token

# Step 6 - Database schema objects creation
RAILS_ENV=production bundle exec rake db:migrate

# Step 7 - Database default data set
RAILS_ENV=production REDMINE_LANG=en bundle exec rake redmine:load_default_data

# Step 8 - File system permissions
mkdir -p tmp tmp/pdf public/plugin_assets
sudo chown -R $REDMINE_USER:$REDMINE_GROUP files log tmp public/plugin_assets
sudo chmod -R 755 files log tmp public/plugin_assets

# Step 9 - Test the installation
bundle exec ruby script/rails server webrick -e production
