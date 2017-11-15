
# kill the testing process if it is still running after finishing a scenario,
# use @keep_running tag to avoid killing the process
After('~@keep_running') do
  return unless @app_pid
  begin
    Process.waitpid(@app_pid, Process::WNOHANG)
    puts "The process is still running, sending TERM signal..."
    # the minus flag sends the signal to the whole process group
    Process.kill("-TERM", @app_pid)
    sleep(5)
    Process.waitpid(@app_pid, Process::WNOHANG)
    puts "The process is still running, sending KILL signal..."
    Process.kill("-KILL", @app_pid)
  rescue Errno::ECHILD
    # the process has exited
    @app_pid = nil
  end
end

 