require 'log'
require 'networking/tcp'

BBFS::Params.log_write_to_console = 'true'
BBFS::Params.log_debug_level = 1
BBFS::Params.log_param_number_of_mega_bytes_stored_before_flush = 0
BBFS::Params.log_param_max_elapsed_time_in_seconds_from_last_flush = 0

BBFS::Log.init

def server_receive_obj(addr_info, hello_msg)
  BBFS::Log.debug1(hello_msg)
  BBFS::Log.debug1(addr_info.inspect)
end

def client_receive_obj(hello_msg)
  BBFS::Log.debug1(hello_msg)
  $tcp_client.send_obj('Hello again.')
end

BBFS::Log.info('Creating TCP client and server.')
$tcp_server = BBFS::Networking::TCPServer.new(5555, method(:server_receive_obj))
#sleep 1
$tcp_client = BBFS::Networking::TCPClient.new('localhost', 5555, method(:client_receive_obj))
#sleep 0.1
#BBFS::Log.info('Wait for the connection to be established.')

BBFS::Log.info('Sending hello...')
BBFS::Log.info("send_obj:#{$tcp_client.send_obj('Hello from client.')}")
#$tcp_server.send_obj('Hello from server.')

BBFS::Log.info('Waiting on threads.')
# Wait for all threads (don't exit).
$tcp_server.tcp_thread.join
$tcp_client.tcp_thread.join
BBFS::Log.info('Should not get here.')
