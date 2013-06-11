require 'fileutils'
require 'set'
require 'thread'

require 'content_data'
require 'content_server/content_receiver'
require 'content_server/queue_indexer'
require 'content_server/queue_copy'
require 'content_server/remote_content'
require 'file_indexing'
require 'file_monitoring'
require 'log'
require 'networking/tcp'
require 'params'
require 'process_monitoring/thread_safe_hash'
require 'process_monitoring/monitoring'
require 'process_monitoring/monitoring_info'

# Content server. Monitors files, index local files, listen to backup server content,
# copy changes and new files to backup server.
module ContentServer
  # Backup server specific flags
  Params.string('content_server_hostname', nil, 'IP or DNS of backup server.')
  Params.integer('content_server_data_port', 3333, 'Port to copy content data from.')
  Params.integer('content_server_files_port', 4444, 'Listening port in backup server for files')
  Params.integer('backup_check_delay', 5, 'Delay in seconds between two content vs backup checks.')

  def run_backup_server
    Log.info('Start backup server')
    Thread.abort_on_exception = true
    all_threads = []

    # create general tmp dir
    FileUtils.mkdir_p(Params['tmp_path']) unless File.directory?(Params['tmp_path'])
    # init tmp content data file
    tmp_content_data_file = Params['tmp_path'] + '/backup.data'

    if Params['enable_monitoring']
      Log.info("Initializing monitoring of process params on port:#{Params['process_monitoring_web_port']}")
      Params['process_vars'] = ThreadSafeHash::ThreadSafeHash.new
      Params['process_vars'].set('server_name', 'backup_server')
    end

    # # # # # # # # # # # #
    # Initialize/Start monitoring
    Log.info('Start monitoring following directories:')
    Params['monitoring_paths'].each {|path|
      Log.info("  Path:'#{path['path']}'")
    }
    monitoring_events = Queue.new
    fm = FileMonitoring::FileMonitoring.new
    fm.set_event_queue(monitoring_events)
    # Start monitoring and writing changes to queue
    all_threads << Thread.new do
      fm.monitor_files
    end

    # # # # # # # # # # # # # #
    # Initialize/Start local indexer
    Log.debug1('Start indexer')
    local_server_content_data_queue = Queue.new
    queue_indexer = QueueIndexer.new(monitoring_events,
                                     local_server_content_data_queue,
                                     Params['local_content_data_path'])
    # Start indexing on demand and write changes to queue
    all_threads << queue_indexer.run

    # # # # # # # # # # # # # # # # # # # # # # # # # # #
    # Initialize/Start backup server content data sender
    Log.debug1('Start backup server content data sender')
    local_dynamic_content_data = ContentData::DynamicContentData.new
    #content_data_sender = ContentDataSender.new(
    #    Params['remote_server'],
    #    Params['remote_listening_port'])
    # Start sending to backup server
    all_threads << Thread.new do
      while true do
        Log.debug1 'Waiting on local server content data queue.'
        cd = local_server_content_data_queue.pop
        #    content_data_sender.send_content_data(cd)
        local_dynamic_content_data.update(cd)
      end
    end

    # # # # # # # # # # # # # # # # # # # # # # # #
    # Start dump local content data to file thread
    Log.debug1('Start dump local content data to file thread')
    all_threads << Thread.new do
      last_data_flush_time = nil
      while true do
        if last_data_flush_time.nil? || last_data_flush_time + Params['data_flush_delay'] < Time.now.to_i
          Log.info "Writing local content data to #{Params['local_content_data_path']}."
          local_dynamic_content_data.last_content_data.to_file(tmp_content_data_file)
          ::FileUtils.mv(tmp_content_data_file, Params['local_content_data_path'])

          last_data_flush_time = Time.now.to_i
        end
        sleep(1)
      end
    end
    Params['backup_destination_folder'] = File.expand_path(Params['monitoring_paths'][0]['path'])
    Log.info("backup_destination_folder is:#{Params['backup_destination_folder']}")
    content_server_dynamic_content_data = ContentData::DynamicContentData.new
    remote_content = ContentServer::RemoteContentClient.new(content_server_dynamic_content_data,
                                                            Params['content_server_hostname'],
                                                            Params['content_server_data_port'],
                                                            Params['backup_destination_folder'])
    all_threads.concat(remote_content.run())

    file_copy_client = FileCopyClient.new(Params['content_server_hostname'],
                                          Params['content_server_files_port'],
                                          local_dynamic_content_data)
    all_threads.concat(file_copy_client.threads)

    # Each
    Log.info('Start remote and local contents comparator')
    all_threads << Thread.new do
      loop do
        sleep(Params['backup_check_delay'])
        local_cd = local_dynamic_content_data.last_content_data()
        remote_cd = content_server_dynamic_content_data.last_content_data()
        diff = ContentData.remove(local_cd, remote_cd)
        #file_copy_client.request_copy(diff) unless diff.empty?
        if !diff.empty?
          Log.info('Start sync check. Backup and remote contents need a sync:')
          Log.debug2("Backup content:\n#{local_cd}")
          Log.debug2("Remote content:\n#{remote_cd}")
          Log.info("Missing contents:\n#{diff}")
          Log.info('Requesting copy files')
          file_copy_client.request_copy(diff)
        else
          Log.info("Start sync check. Local and remote contents are equal. No sync required.")
        end
      end
    end

    # # # # # # # # # # # # # # # # # # # # # # # #
    # Start process vars thread
    if Params['enable_monitoring']
      monitoring_info = MonitoringInfo::MonitoringInfo.new()
      all_threads << Thread.new do
        last_data_flush_time = nil
        while true do
          if last_data_flush_time.nil? || last_data_flush_time + Params['process_vars_delay'] < Time.now
            Params['process_vars'].set('time', Time.now)
            Log.info("process_vars:monitoring queue size:#{monitoring_events.size}")
            Params['process_vars'].set('monitoring queue', monitoring_events.size)
            Log.info("process_vars:content data queue size:#{monitoring_events.size}")
            Params['process_vars'].set('content data queue', local_server_content_data_queue.size)
            last_data_flush_time = Time.now
          end
          sleep(0.3)
        end
      end
    end

    all_threads.each { |t| t.abort_on_exception = true }
    all_threads.each { |t| t.join }
    # Should never reach this line.
  end
  module_function :run_backup_server

end # module ContentServer


