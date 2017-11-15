
require "timeout"
require "socket"

When(/^I start the "(.*)" application$/) do |application|
  start_app(application)
end

Then("I wait for the application to finish") do
  Timeout.timeout(DEFAULT_TIMEOUT) do
    puts "#Waiting... (#{Time.now})"
    Process.wait(@app_pid)
    puts "FINISHED (#{Time.now})"
  end
end

Given("I use an running libyui application on port (\d+)") do | port|
  # set_port
  pending
end


