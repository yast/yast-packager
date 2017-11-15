
require "timeout"
require "socket"

DEFAULT_TIMEOUT = 15

def set_port
  # 14155 is currently an unassigned port
  ENV["YUI_HTTP_PORT"] ||= "14155"
  ENV["YUI_HTTP_PORT"]
end

# is the target port open?
# @param [Integer] port the port number
# @return [Boolean] true if the port is open, false otherwise
def port_open?(host, port)
  begin
    TCPSocket.new(host, port).close
    true
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    false
  end
end

def wait_for_port(host, port)
  Timeout.timeout(DEFAULT_TIMEOUT) do
    loop do
      sleep(1)
      puts "Waiting for #{host}:#{port}..."
      break if port_open?(host, port)
    end
  end
end

def start_app(application)
  @app_host = "localhost"
  @app_port = set_port
  # create a new process group so we can easily kill it will all subprocesses
  @app_pid = spawn(application, pgroup: true)
  wait_for_port(@app_host, @app_port)
end

Given(/^I start the "(.*)" application$/) do |application|
  start_app(application)
end

Then(/^I wait for the application to finish(?: for up to (\d+) seconds)?$/) do |seconds|
  Timeout.timeout(seconds || DEFAULT_TIMEOUT) do
    Process.wait(@app_pid)
  end
end
