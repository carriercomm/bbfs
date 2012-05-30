require 'sys/uname'
require 'test/unit'
require 'run_in_background'

module BBFS
  # TODO break to number of small tests according to functionality
  # TODO rewrite with Shoulda/RSpec
  class TestRunInBackground < Test::Unit::TestCase
    #include BBFS::RunInBackground

    if RUBY_PLATFORM =~ /linux/ or RUBY_PLATFORM =~ /darwin/
      OS = :LINUX
    elsif RUBY_PLATFORM =~ /mingw/ or RUBY_PLATFORM =~ /ms/ or RUBY_PLATFORM =~ /win/
      OS = :WINDOWS
    else
      raise "Unsupported platform #{RUBY_PLATFORM}"
    end

    def setup
      @good_daemon = "good_daemon_test"
      @good_daemonize = "good_daemonize_test"
      @good_win32daemon = "good_win32daemon_test"
      @bad_daemon = "bad_daemon_test"
      @binary = File.join(File.dirname(File.expand_path(__FILE__)), "test_app")
      @binary.tr!('/','\\') if OS == :WINDOWS
      File.chmod(0755, @binary) if OS == :LINUX && !File.executable?(@binary)
      @absent_binary = File.join(File.dirname(File.expand_path(__FILE__)), "test_app_absent")
    end

    def test_functionality
      if OS == :WINDOWS && Sys::Uname.sysname =~ /(Windows 7)/
        skip "This test shouldn't be run on #{$1}"
      end

      # test start
      # test application should actually start here
      assert_nothing_raised{ RunInBackground.start(@binary, ["1000"], @good_daemon) }
      assert_raise(ArgumentError) { RunInBackground.start(@absent_binary, ["1000"], @bad_daemon) }

      # start arguments have to be defined
      assert_raise(ArgumentError) { RunInBackground.start(["1000"], @bad_daemon) }
      assert_raise(ArgumentError) { RunInBackground.start(nil, ["1000"], @bad_daemon) }
      assert_raise(ArgumentError) { RunInBackground.start(@absent_binary, nil, @bad_daemon) }
      assert_raise(ArgumentError) { RunInBackground.start(@absent_binary, ["1000"], nil) }

      # test exists?
      assert_raise(ArgumentError) { RunInBackground.exists? }
      assert_equal(false, RunInBackground.exists?(@bad_daemon))
      assert_equal(true, RunInBackground.exists?(@good_daemon))

      # test running?
      # if stop method will be public need to add test checks actually stopped daemon
      assert_raise(ArgumentError) { RunInBackground.running? }
      assert_raise(ArgumentError) { RunInBackground.running?(@bad_daemon) }
      assert_equal(true, RunInBackground.running?(@good_daemon))

      # test daemonazing (start!)
      # from the nature of daemonization need to run it from another process that will be daemonized
      ruby = (OS == :WINDOWS ? RunInBackground::RUBY_INTERPRETER_PATH : "ruby")
      cmd = "#{ruby} -Ilib #{@binary} 50 #{@good_daemonize}"
      pid = spawn(cmd)
      Process.waitpid pid
      # checking that it indeed was daemonized
      # e.i. process was killed and code rerun in background
      sleep 2
      assert_raise(Errno::ESRCH) { Process.kill(0, pid) }
      assert_equal(true, RunInBackground.exists?(@good_daemonize))
      assert_equal(true, RunInBackground.running?(@good_daemonize))

      # test running win32 specific daemon (start_win32service)
      # wrapper script will be run
      if OS == :WINDOWS
        win32service_arg = [RunInBackground::RUBY_INTERPRETER_PATH, @binary, 1000]
        assert_nothing_raised{
          RunInBackground.start_win32service(RunInBackground::WRAPPER_SCRIPT,
                                             win32service_arg, @good_win32daemon)
        }
        assert_equal(true, RunInBackground.exists?(@good_win32daemon))
        assert_equal(true, RunInBackground.running?(@good_win32daemon))
      else
        assert_raise(NotImplementedError) {
          RunInBackground.start_win32service(@absent_binary, [], @bad_daemon)
        }
      end

      # uncomment following lines if there is a suspicion that something gone wrong
      # inspired by bug caused by coworking of daemon_wrapper an logger
      #sleep 10
      #assert_equal(true, RunInBackground.running?(@good_daemon))
      #assert_equal(true, RunInBackground.running?(@good_daemonize))
      #assert_equal(true, RunInBackground.running?(@good_win32daemon))

      # test delete
      # test application should actually stop here
      assert_raise(ArgumentError) { RunInBackground.delete }
      assert_raise(ArgumentError) { RunInBackground.delete(@bad_daemon) }
      assert_nothing_raised { RunInBackground.delete(@good_daemon) }
      assert_equal(false, RunInBackground.exists?(@good_daemon))

      if RunInBackground.exists?(@good_daemonize)
        assert_nothing_raised { RunInBackground.delete(@good_daemonize) }
        assert_equal(false, RunInBackground.exists?(@good_daemonize))
      end

      if RunInBackground.exists?(@good_win32daemon)
        assert_nothing_raised { RunInBackground.delete(@good_win32daemon) }
        assert_equal(false, RunInBackground.exists?(@good_win32daemon))
      end
    end

    def teardown
      RunInBackground.delete @good_daemon if RunInBackground.exists? @good_daemon
      RunInBackground.delete @good_daemonize if RunInBackground.exists? @good_daemonize
      RunInBackground.delete @good_win32daemon if RunInBackground.exists? @good_win32daemon
    end
  end
end
