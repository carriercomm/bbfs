require 'file_indexing/index_agent'
require 'file_indexing/indexer_patterns'
require 'log'

module ContentServer

  Params.integer('data_flush_delay', 300, 'Number of seconds to delay content data file flush to disk.')

  # Simple indexer, gets inputs events (files to index) and outputs
  # content data updates into output queue.
  class QueueIndexer

    def initialize(input_queue, output_queue, content_data_path)
      @input_queue = input_queue
      @output_queue = output_queue
      @content_data_path = content_data_path
      @last_data_flush_time = nil
    end

    def run
      server_content_data = ContentData::ContentData.new
      # Shallow check content data files.
        tmp_content_data = ContentData::ContentData.new
        tmp_content_data.from_file(@content_data_path) if File.exists?(@content_data_path)
        #Loop over instances from file
        #  If file time and size matches then add it to DB
        #  Else, monitor the path again
        tmp_content_data.each_instance { |checksum, size, content_mod_time, instance_mod_time, server, device, path|
          if File.exists?(path)
            file_mtime, file_size = File.open(path) { |f| [f.mtime, f.size] }
            if ((file_size == size) &&
                (file_mtime.to_i == instance_mod_time))
              Log.debug1("file exists: #{path}")
              # add instance to local DB
              server_content_data.add_instance(checksum, size, server,
                                               device, path, instance_mod_time)
            else
              Log.debug1("changed: #{path}")
              # Add non existing and changed files to index queue.
              @input_queue.push([FileMonitoring::FileStatEnum::STABLE, path])
            end
          else  # File.exists?(path) TODO: need to change code
            Log.debug1("changed: #{path}")
            # Add non existing and changed files to index queue.
            @input_queue.push([FileMonitoring::FileStatEnum::STABLE, path])
          end
        }


      # Start indexing on demand and write changes to queue
      thread = Thread.new do
        while true do
          Log.debug1 'Waiting on index input queue.'
          state, is_dir, path = @input_queue.pop
          Log.debug1 "event: #{state}, #{is_dir}, #{path}."

            # index files and add to copy queue
            # delete directory with it's sub files
            # delete file
            if state == FileMonitoring::FileStatEnum::STABLE && !is_dir
              Log.info "Indexing file:'#{path}'."
              index_agent = FileIndexing::IndexAgent.new
              indexer_patterns = FileIndexing::IndexerPatterns.new
              indexer_patterns.add_pattern(path)
              index_agent.index(indexer_patterns, server_content_data)
              Log.debug1("Failed files: #{index_agent.failed_files.to_a.join(',')}.") \
                  if !index_agent.failed_files.empty?
              Log.debug1("indexed content #{index_agent.indexed_content}.")
              # merge indexed content into server content data
              ContentData.merge_override_b(index_agent.indexed_content, server_content_data)
            elsif ((state == FileMonitoring::FileStatEnum::NON_EXISTING ||
                state == FileMonitoring::FileStatEnum::CHANGED) && !is_dir)
              # If file content changed, we should remove old instance.
              candidate_location = FileIndexing::IndexAgent.global_path(path)
              # Check if deleted file exists at content data.
              Log.debug1("Instance candidate to remove: #{candidate_location}")
              server_content_data.each_instance { |checksum, size, content_mod_time, instance_mod_time, server, device, path|
                tmp_location = "%s,%s,%s" % [server, device, path]
                if (tmp_location == candidate_location)
                  if !shallow_check(path, size, instance_mod_time)
                    server_content_data.remove_instance(tmp_location, checksum)
                  else
                    Log.error("Code should not reach this point")
                  end
                  break
                end
              }
            elsif state == FileMonitoring::FileStatEnum::NON_EXISTING && is_dir
              Log.debug1("NonExisting/Changed: #{path}")
              # Remove directory but only when non-existing.
              Log.debug1("Directory to remove: #{path}")
              global_dir = FileIndexing::IndexAgent.global_path(path)
              server_content_data = ContentData.remove_directory(
              server_content_data, global_dir)
            else
              Log.debug1("This case should not be handled: #{state}, #{is_dir}, #{path}.")
            end
            if @last_data_flush_time.nil? || @last_data_flush_time + Params['data_flush_delay'] < Time.now.to_i
              Log.debug1 "Writing server content data to #{@content_data_path}."
              server_content_data.to_file(@content_data_path)
              @last_data_flush_time = Time.now.to_i
            end
            Log.debug1 'Adding server content data to queue.'
            @output_queue.push(ContentData::ContentData.new(server_content_data))
          end  # while true do
        end  # Thread.new do
        thread
      end  # def run

      # Check file existence, check it's size and modification date.
      # If something wrong reindex the file and update content data.
      def shallow_check(file_name, file_size, file_mod_time)
        shallow_instance = FileIndexing::IndexAgent.create_shallow_instance(file_name)
        return false unless shallow_instance
        return (shallow_instance[0] == file_size &&
                shallow_instance[2] == file_mod_time)
      end

  end  # class QueueIndexer
end

