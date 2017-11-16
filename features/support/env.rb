
srcdir = File.expand_path("../../../src", __FILE__)
y2dirs = ENV.fetch("Y2DIR", "").split(":")
ENV["Y2DIR"] = y2dirs.unshift(srcdir).join(":")

# use the aruba extension, it provides many generic step definitions
# for running commands and checking files
require "aruba/cucumber"

# kill the testing process if it is still running after finishing a scenario,
# use @keep_running tag to avoid killing the process
After('not @keep_running') do
  if @app_pid
    begin
      Process.waitpid(@app_pid, Process::WNOHANG)
      puts "The process is still running, sending TERM signal..."
      # the minus flag sends the signal to the whole process group
      Process.kill("-TERM", @app_pid)
      sleep(5)
      Process.waitpid(@app_pid, Process::WNOHANG)
      puts "The process is still running, sending KILL signal..."
      Process.kill("-KILL", @app_pid)
    rescue Errno::ECHILD, Errno::ESRCH
      # the process has exited
      @app_pid = nil
    end
  end
end

# allow a short delay between the steps to watch the UI changes and reactions
AfterStep do
  delay = ENV["STEP_DELAY"].to_f
  sleep(delay) if delay > 0
end
