
require "json"
require "net/http"
require "uri"
require "timeout"
require "socket"

def read_widgets(type: nil, label:nil, id: nil)
  uri = URI("http://#{@app_host}:#{@app_port}/widgets")
  params = {}
  params[:type] = type if type
  params[:label] = label if label
  params[:id] = id if id
  uri.query = URI.encode_www_form(params)

  res = Net::HTTP.get_response(uri)
  if res.is_a?(Net::HTTPSuccess)
    return JSON.parse(res.body)
  elsif res.is_a?(Net::HTTPNotFound)
    raise "Widget not found"
  else
    raise "Unknown error"
  end
end

def read_dialog_heading
  widgets = read_widgets(type: "YWizard")
  widgets.first["debug_label"]
end

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
      puts "Waiting for port #{host}:#{port}..."
      break if port_open?(host, port)
    end
  end
end

def start_app(application)
  @app_host = "localhost"
  @app_port = set_port
  # start in a new process group so we can easily kill it will all subprocesses
  @app_pid = spawn(application, pgroup: true)
  wait_for_port(@app_host, @app_port)
end


After do
  return unless @app_pid
  begin
    Process.waitpid(@app_pid, Process::WNOHANG)
    puts "The process is still running, sending TERM singal..."
    # the minus flag sends the signal to the whole process group
    Process.kill("-TERM", @app_pid)
    sleep(5)
    Process.waitpid(@app_pid, Process::WNOHANG)
    puts "The process is still running, sending KILL singal..."
    Process.kill("-KILL", @app_pid)
  rescue Errno::ECHILD
    # the process has already exited
  end
end

 