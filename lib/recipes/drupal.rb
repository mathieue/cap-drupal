Capistrano::Configuration.instance(:must_exist).load do
  # nb of dumps to keep after a clean
  set :max_keep_dump, 5
  # nb of ugc files dirs backup
  set :max_keep_backup, 3

  set :user, "cap"
  namespace :drupal do

    desc "clear all drupal caches"
    task :clearcache, :roles => :db do
      run "sudo drush -r \"#{deploy_to}\" cc all"
    end

    namespace :clean do
      namespace :db do
        desc "list db dumps to delete"
        task :check, :roles => :db do
          dumps_to_delete do |dump|
            puts "will delete #{dump}"
          end
        end
        desc "delete db dumps over max_keep_dump"
        task :commit, :roles => :db do
          dumps_to_delete do |dump|
            run "rm #{dump}"
          end
        end
      end
      namespace :ugc do
        desc "list ugc backups to delete"
        task :check, :roles => :web do
          backups_to_delete do |backup|
            puts "will delete #{backup}"
          end
        end
        desc "delete ugc backups over max_keep_backup"
        task :commit, :roles => :web do
          backups_to_delete do |backup|
            run "rm -rf #{backup}"
          end
        end
      end
    end

    namespace :db do
      desc "dump the db to cap user home directory"
      task :dump, :roles => :db do
        filename = "#{application}-#{stage}-#{now}.sql"
        run "sudo drush -r \"#{deploy_to}\" sql-dump > ~/#{filename}"
      end

      desc "get the latest db dump to current local dir"
      task :latest, :roles => :db do
        dumps = capture("ls -xt ~/#{application}-#{stage}-*sql").split.reverse
        get(dumps.last, "#{dumps.last.split('/').last}")
      end

      desc "dump the db and download to local dir"
      task :download, :roles => :db do
        dump
        latest
      end
    end

    # user generated content
    namespace :ugc do

      desc "show the ugc files current size"
      task :size, :role => :web do
        run "du -sh #{ugc_path}"
      end

      desc "copy user generated content to cap user home"
      task :backup, :role => :web do
        size
        dirname = "~/#{application}-#{stage}-#{now}-ugc"
        run "sudo cp -a #{ugc_path} #{dirname}"
        run "sudo chown -R #{user}:#{user} #{dirname}"
        run "touch #{dirname}"
      end

      desc "get the latest ugc backup"
      task :latest, :role => :web do
        backups = capture("ls -dxt ~/#{application}-#{stage}-*-ugc").split.reverse
        size
        puts "rsync, this could take a while..."
        system "rsync -lrp --human-readable --progress --delete #{user}@#{application_host}:#{backups.last}/ #{ugc_local_cache}"
        puts "local rsync from local cache to final dir"
        system "rsync -lrp #{ugc_local_cache}/ #{backups.last.split('/').last}"
      end

      desc "backup and dowload user generated content"
      task :download, :roles => :db do
        backup
        latest
      end
    end
  end

  before "drupal:db:dump", "drupal:clearcache"

  # used to name new files
  def now
    now = Time.now.strftime("%Y-%m-%d-%H.%M.%S")
  end

  def ugc_local_cache
    "tmp-#{application}"
  end

  def dumps_to_delete        
    dumps = capture("ls -xt ~/#{application}-#{stage}-*sql").split
    dumps.slice!(0, max_keep_dump)
    dumps.each do |dump|
      yield dump
    end
  end

  def backups_to_delete        
    backups = capture("ls -dxt ~/#{application}-#{stage}-*-ugc").split
    backups.slice!(0, max_keep_backup)
    backups.each do |backup|
      yield backup
    end
  end
end
