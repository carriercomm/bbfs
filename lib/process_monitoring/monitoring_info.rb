require 'eventmachine'
require 'json'
require 'net/http'
require 'thin'
require 'sinatra'

require 'content_server/server'
require 'params'

# Set up event machine to exit on ctrl+c.
EventMachine.schedule do
  trap("INT") do
    puts "Caught SIGINT"
   # EventMachine.stop # this is useless
    exit                  # exit # this stops the EventMachine
  end
end

# This module export process info to http port, that way the user may access with the
# browser to the process to see what is happening inside, what is it's state and parameters.
module MonitoringInfo

  Params.integer('process_monitoring_web_port', 5555,
                 'The port from which monitoring data will be served as http.')

  class MonitoringInfo
    attr_reader :thread

    def initialize()
      @web_interface = Sinatra.new {
        set :bind, '0.0.0.0'
        get('/') { MonitoringInfo.get_json($process_vars.clone) }
      }
      @web_interface.set(:port, Params['process_monitoring_web_port'])
      @thread = Thread.new do
        @web_interface.run!
      end
    end

    def self.get_json(hash)
      return '' if !hash.is_a?(Hash)

      entries = []
      hash.each do |key, value|
        entries << "{#{key}:#{value}}"
      end

      return entries.join(" , ")
    end

    def self.get_html (hash, opts = {})
      return if !hash.is_a?(Hash)

      indent_level = opts.fetch(:indent_level) { 0 }

      out = " " * indent_level + "<ul>\n"

      hash.each do |key, value|
        out += " " * (indent_level + 2) + "<li><strong>#{key}:</strong>"

        if value.is_a?(Hash)
          out += "\n" + get_html(value, :indent_level => indent_level + 2) + " " * (indent_level + 2) + "</li>\n"
        else
          out += " <span>#{value}</span></li>\n"
        end
      end

      out += " " * indent_level + "</ul>\n"
    end

    def self.get_remote_monitoring_info(host, port)
      begin
        JSON.parse(Net::HTTP.get(URI("http://#{host}:#{port}/")))
      rescue Errno::ECONNREFUSED => e
        ''
      end
    end
  end
end
