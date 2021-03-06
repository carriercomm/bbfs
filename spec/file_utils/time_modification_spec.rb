# NOTE Code Coverage block must be issued before any of your application code is required
if ENV['BBFS_COVERAGE']
  require_relative '../spec_helper.rb'
  SimpleCov.command_name 'file_utils'
end
require 'fileutils'
require 'time'
require 'rspec'

require 'content_data'
require 'file_indexing'
require 'file_utils'
require 'log'
require 'params'

module FileUtils
  def FileUtils.parse_time time_str
    return nil unless time_str.instance_of? String
    seconds_from_epoch = Integer time_str  # Not using to_i here because it does not check string is integer.
    time = Time.at seconds_from_epoch
  end

  module Spec
    describe 'Time Modification Test' do
      # directory where tested files will be placed: __FILE__/time_modification_test
      TIME_MODIFICATION_RESOURCES_DIR = File.expand_path(File.dirname(__FILE__) + "/time_modification_test")
      # minimal time that will be inserted in content
      MOD_TIME_CONTENTS = FileUtils.parse_time("1306527039")
      # minimal time that will be inserted in instance
      MOD_TIME_INSTANCES = FileUtils.parse_time("1306527039")
      #time_str =  "2002/02/01 02:23:59.000"
      #MOD_TIME_INSTANCES = Time.strftime( time_str, '%Y/%m/%d %H:%M:%S.%L' )
      DEVICE_NAME = "hd1"

      @input_db
      @mod_content_checksum = nil  # checksum of the content that was manually modified
      @mod_instance_checksum = nil  # checksum of the instance that was manually modified

      before :all do
        Params.init Array.new
        # must preced Log.init, otherwise log containing default values will be created
        Params['log_write_to_file'] = false
        Params['log_write_to_console'] = false
        Params['log_debug_level'] = 1
        Log.init

        sizes = [500, 1000, 1500]
        numb_of_copies = 2
        test_file_name = "test_file"

        Dir.mkdir(TIME_MODIFICATION_RESOURCES_DIR) unless (File.exists?(TIME_MODIFICATION_RESOURCES_DIR))
        raise "Can't create writable working directory: #{TIME_MODIFICATION_RESOURCES_DIR}" unless \
              (File.exists?(TIME_MODIFICATION_RESOURCES_DIR) and File.writable?(TIME_MODIFICATION_RESOURCES_DIR))
        # prepare files for testing
        sizes.each do |size|
          file_path = "#{TIME_MODIFICATION_RESOURCES_DIR}/#{test_file_name}.#{size}"
          file = File.open(file_path, "w", 0777) do |file|
            content = Array.new
            size.times do |i|
              content.push(sprintf("%5d ", i))
            end
            file.puts(content)
          end
          File.utime File.atime(file_path), MOD_TIME_CONTENTS, file_path
          numb_of_copies.times do |i|
            ::FileUtils.cp(file_path, "#{file_path}.#{i}")
          end
        end

        indexer = FileIndexing::IndexAgent.new
        patterns = FileIndexing::IndexerPatterns.new
        patterns.add_pattern(TIME_MODIFICATION_RESOURCES_DIR + '\*')
        indexer.index(patterns)

        @input_db = indexer.indexed_content
      end

      # This test compares two ways of ruby + OS to get mtime (modification file) of a file.
      # We can see that in Windows there is a difference.
      it 'test local os' do
        Dir.mkdir(TIME_MODIFICATION_RESOURCES_DIR) unless (File.exists?(TIME_MODIFICATION_RESOURCES_DIR))
        file_path = "#{TIME_MODIFICATION_RESOURCES_DIR}/local_os_test.test"
        file = File.open(file_path, "w", 0777) do |file|
          file.puts("kuku")
        end
        file_stats = File.stat(file_path)
        Log.info "MOD_TIME_CONTENTS: #{MOD_TIME_CONTENTS}."
        Log.info "MOD_TIME_CONTENTS: #{MOD_TIME_CONTENTS.to_i}."
        Log.info "file_stat.mtime: #{file_stats.mtime}."
        Log.info "file_stat.mtime: #{file_stats.mtime.to_i}."
        Log.info "File.mtime: #{File.mtime(file_path)}."
        Log.info "File.mtime: #{File.mtime(file_path).to_i}."
        File.utime File.atime(file_path), MOD_TIME_CONTENTS, file_path
        file_stats = File.stat(file_path)
        Log.info "file_stat.mtime: #{file_stats.mtime}."
        Log.info "file_stat.mtime: #{file_stats.mtime.to_i}."
        Log.info "File.mtime: #{File.mtime(file_path)}."
        Log.info "File.mtime: #{File.mtime(file_path).to_i}."

        file_mtime = nil
        file = File.open(file_path, "r") do |file|
          Log.info "file.open.mtime = #{file.mtime}"
          Log.info "file.open.mtime = #{file.mtime.to_i}"
          file_mtime = file.mtime
        end

        file_mtime.should == MOD_TIME_CONTENTS

        # !!! This fails on windows with different timezone
        # file_stats.mtime.should == MOD_TIME_CONTENTS
      end

      it 'test modify' do
        # modified ContentData. Test files also were modified.
        mod_db = FileUtils.unify_time(@input_db)

        Log.info "==============="
        Log.info @input_db.to_s
        Log.info "==============="

        # checking that content was modified according to the instance with minimal time
        mod_db.each_instance { |checksum, size, content_mod_time, instance_mod_time, server, path|
          next unless checksum.eql?(@mod_instance_checksum)
          content_time =  FileUtils.parse_time(content_mod_time.to_s)
          content_time.should == MOD_TIME_INSTANCES
          instance_time =  FileUtils.parse_time(instance_mod_time.to_s)
          instance_time.should == MOD_TIME_INSTANCES
        }

        # checking that files were actually modified
        # TODO(kolman): Decide whether files should be updated or not and change the implementation.
        mod_db.each_instance { |checksum, size, content_mod_time, instance_mod_time, server, path|
          indexer = FileIndexing::IndexAgent.new  # (instance.server_name, instance.device)
          patterns = FileIndexing::IndexerPatterns.new
          patterns.add_pattern(File.dirname(path) + '/*')     # this pattern index all files
          indexer.index(patterns, mod_db)
          mod_db.should == indexer.indexed_content
          break
        }
      end
    end
  end
end
