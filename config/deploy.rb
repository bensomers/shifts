# == DEPLOYMENT DEFAULTS =========
default_domain = ENV['DOMAIN'] ? ENV['DOMAIN'] : "mahi.its.yale.edu"
default_application_prefix = ENV['PREFIX'] ? ENV['PREFIX'] : "test"
default_branch = ENV['BRANCH'] ? ENV['BRANCH'] : "master"

# == INITIAL CONFIG ==============
set :application, "shifts"
set :repository,  "git@github.com:YaleSTC/shifts.git"
set :apache_config_dir, "/etc/apache2/vhosts.d"
set :document_root, "/srv/www/htdocs"

set :user, "deploy"
set :runner, "deploy"
set :use_sudo, false

set :domain, Capistrano::CLI.ui.ask("Deployment server hostname (default #{default_domain}): ") unless ENV['DOMAIN']
set :application_prefix, Capistrano::CLI.ui.ask("Application prefix (default #{default_application_prefix}): ") unless ENV['PREFIX']
set :branch, Capistrano::CLI.ui.ask("Deployment branch (default #{default_branch}): ") unless ENV['BRANCH']

#Set Variables to default if specified from command line or left blank
set :domain, default_domain if (ENV['DOMAIN'] || fetch(:domain) == "")
set :application_prefix, default_application_prefix if (ENV['PREFIX'] || fetch(:application_prefix) == "")
set :branch, default_branch if (ENV['BRANCH'] || fetch(:branch) == "")

set :deploy_to, "/srv/www/rails/#{application}/#{application_prefix}"

set :scm, :git
set :scm_verbose, false

role :app, "#{domain}"
role :web, "#{domain}"
role :db,  "#{domain}", :primary => true


# == CONFIG ====================================================================

namespace :init do
  namespace :config do
    desc "Create database.yml"
    task :database do
      set :mysql_user, Capistrano::CLI.ui.ask("deployment host database user name: ")
      set :mysql_pass, Capistrano::CLI.password_prompt("deployment host database password: ")
      database_configuration =<<-EOF
---
production:
  adapter: mysql
  database: #{application}_#{application_prefix}_production
  host: localhost
  user: #{mysql_user}
  password: #{mysql_pass}

EOF
      run "mkdir -p #{shared_path}/config"
      put database_configuration, "#{shared_path}/config/database.yml"
    end

    desc "Enter Hoptoad API code"
    task :hoptoad do
      set :api_key, Capistrano::CLI.ui.ask("Hoptoad API Key: ")
      hoptoad_config=<<-EOF
HoptoadNotifier.configure do |config|
  config.api_key = '#{api_key}'
end

EOF
      put hoptoad_config, "#{shared_path}/config/hoptoad.rb"
    end

    desc "Symlink shared configurations to current"
    task :localize, :roles => [:app] do

      run "ln -nsf #{shared_path}/config/database.yml #{current_path}/config/database.yml"
      #Temporarily disabled until hoptoad integration is complete
      run "ln -nsf #{shared_path}/config/hoptoad.rb #{current_path}/config/initializers/hoptoad.rb"

      run "mkdir -p #{shared_path}/log"
      run "mkdir -p #{shared_path}/pids"
      run "mkdir -p #{shared_path}/sessions"
      run "mkdir -p #{shared_path}/system/datas"
      run "ln -nsfF #{shared_path}/log/ #{current_path}/log"
      run "ln -nsfF #{shared_path}/pids/ #{current_path}/tmp/pids"      
      run "ln -nsfF #{shared_path}/sessions/ #{current_path}/tmp/sessions"
      run "ln -nsfF #{shared_path}/system/ #{current_path}/public/system"
    end    
  end  
end

# == DATABASE ==================================================================
# == BACKUP DB TASK

namespace :db do
  desc "Backup your Database to #{shared_path}/db_backups"
  task :backup, :roles => :db, :only => {:primary => true} do
    set :db_user, Capistrano::CLI.ui.ask("Database user: ")
    set :db_pass, Capistrano::CLI.password_prompt("Database password: ")
    now = Time.now
    run "mkdir -p #{shared_path}/backup"
    backup_time = [now.year,now.month,now.day,now.hour,now.min,now.sec].join('-')
    set :backup_file, "#{shared_path}/backup/#{application}-snapshot-#{backup_time}.sql"
    run "mysqldump --add-drop-table -u #{db_user} -p #{db_pass} #{application}_#{application_prefix}_production --opt | bzip2 -c > #{backup_file}.bz2"
  end

end

#== DEPLOYMENT
#=====================================================================

#before "deploy:migrate", "db:backup"
namespace :deploy do

  desc "Initializer. Runs setup, copies code, creates and migrates db, and starts app"
  task :first, :roles => :app do
    setup
    update
    create_db
    passenger_config
    migrate
    restart_apache
  end

  desc "Create vhosts file for Passenger config"
  task :passenger_config, :roles => :app do
    run "#{sudo} sh -c \'echo \"RailsBaseURI /#{application_prefix}\" > #{apache_config_dir}/rails_#{application}_#{application_prefix}.conf\'"
    run "#{sudo} ln -s #{deploy_to}/current/public #{document_root}/#{application_prefix}"    
  end

  desc "Create database"
  task :create_db, :roles => :app do
    run "cd #{release_path} && #{sudo} rake db:create RAILS_ENV=production"
  end

  task :start, :roles => :app do
    run "touch #{current_release}/tmp/restart.txt"
  end

  task :stop, :roles => :app do
    # Do nothing.
  end

  desc "Restart Application"
  task :restart, :roles => :app do
    run "touch #{current_release}/tmp/restart.txt"
  end

  desc "Restart Apache"
  task :restart_apache, :roles => :app do
      run "#{sudo} /etc/init.d/apache2 restart"
  end

  desc "Update the crontab file"
  task :update_crontab, :roles => :app do
    run "cd #{release_path} && whenever --update-crontab #{application}-#{application_prefix} --set 'rails_root=#{current_path}'"
  end

end

after "deploy:setup", "init:config:database"
after "deploy:setup", "init:config:hoptoad"
after "deploy:symlink", "init:config:localize"
after "deploy:symlink", "deploy:update_crontab"
after "deploy", "deploy:cleanup"
after "deploy:migrations", "deploy:cleanup"