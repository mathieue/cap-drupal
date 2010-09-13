Capistrano::Configuration.instance(:must_exist).load do
  # nb of dumps to keep after a clean
  # nb of ugc files dirs backup

  unless exists?(:max_keep_dump)
    set :max_keep_dump, 5
  end

  unless exists?(:max_keep_backup)
    set :max_keep_backup, 3
  end

  namespace :drupal do

    desc <<-DESC 
    Clear all drupal caches. Invoke drush cc all.
    DESC
    task :clearcache, :roles => :db do
      run "sudo drush -r \"#{deploy_to}\" cc all"
    end

    namespace :clean do
      namespace :db do
        desc <<-DESC 
            List db dumps to delete. Based on timestamp, show the oldest
            which exceed max_keep_dump. 
        DESC
        task :check, :roles => :db do
          dumps_to_delete do |dump|
            puts "will delete #{dump}"
          end
        end
        desc <<-DESC 
            Delete db dumps over max_keep_dump. 
        DESC
        task :commit, :roles => :db do
          dumps_to_delete do |dump|
            run "rm #{dump}"
          end
        end
      end
      namespace :ugc do
        desc <<-DESC 
            List ugc backups to delete. Based on timestamp, show the oldest
            which exceed max_keep_dump. 
        DESC
        task :check, :roles => :web do
          backups_to_delete do |backup|
            puts "will delete #{backup}"
          end
        end
        desc <<-DESC 
            Delete ugc backups over max_keep_backup
        DESC
        task :commit, :roles => :web do
          backups_to_delete do |backup|
            run "rm -rf #{backup}"
          end
        end
      end
    end

    namespace :db do
      desc <<-DESC 
        Dump the db to cap user home directory.
      DESC
      task :dump, :roles => :db do
        filename = "#{application}-#{stage}-#{now}.sql"
        run "sudo drush -r \"#{deploy_to}\" sql-dump > ~/#{filename}"
      end

      desc <<-DESC 
        Download latest db dump to current local dir.
      DESC
      task :latest, :roles => :db do
        dumps = capture("ls -xt ~/#{application}-#{stage}-*sql").split.reverse
        get(dumps.last, "#{dumps.last.split('/').last}")
      end

    desc <<-DESC 
      Dump the db and download to local dir.
    DESC
      task :download, :roles => :db do
        dump
        latest
      end
    end

    # user generated content
    namespace :ugc do

      desc <<-DESC 
        Show the ugc files current size (du -sh).
      DESC
      task :size, :role => :web do
        run "du -sh #{ugc_path}"
      end

      desc <<-DESC 
        Copy user generated content to cap user home.
      DESC
      task :backup, :role => :web do
        size
        dirname = "~/#{application}-#{stage}-#{now}-ugc"
        run "sudo cp -a #{ugc_path} #{dirname}"
        run "sudo chown -R #{user}:#{user} #{dirname}"
        run "touch #{dirname}"
      end

      desc <<-DESC 
        Rsync the latest ugc backup to a local dir.
        Use a local cache dir so rsync do not transfert same files twice.
      DESC
      task :latest, :role => :web do
        backups = capture("ls -dxt ~/#{application}-#{stage}-*-ugc").split.reverse
        size
        puts "rsync, this could take a while..."
        system "rsync -lrp --human-readable --progress --delete #{user}@#{application_host}:#{backups.last}/ #{ugc_local_cache}"
        puts "local rsync from local cache to final dir"
        system "rsync -lrp #{ugc_local_cache}/ #{backups.last.split('/').last}"
      end

      desc <<-DESC 
        Backup and dowload user generated content. 
        Copy on remote to cap home. Then rsync to a local dir.
        Use a local cache dir so rsync do not transfert same files twice.
      DESC
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
