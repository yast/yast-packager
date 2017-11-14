
require "timeout"
require "socket"

DEFAULT_TIMEOUT = 15

def set_port
  # 14155 is currently an unassigned port
  @app_port = ENV["YUI_HTTP_PORT"] || 14155
  ENV["YUI_HTTP_PORT"] = @app_port.to_s
end

# is the target port open?
# @param [Integer] port the port number
# @return [Boolean] true if the port is open, false otherwise
def port_open?(port)
  begin
    TCPSocket.new("localhost", port).close
    true
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
    false
  end
end

def wait_for_port(port)
  Timeout.timeout(DEFAULT_TIMEOUT) do
    loop do
      break if port_open?(port)
      sleep(1)
    end
  end
end

When(/^I start the "(.*)" application$/) do |application|
  set_port
  @pid = spawn(application)
  # wait a bit until the app REST API port is open
  wait_for_port(@app_port)
end

Then("I wait for the application to finish") do
  Timeout.timeout(DEFAULT_TIMEOUT) do
    Process.wait(@pid)
  end
end

Given("I use an running libyui application on port (\d+)") do | port|
  # set_port
  pending
end


