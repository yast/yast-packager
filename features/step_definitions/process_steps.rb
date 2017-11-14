
def set_port(port)
  # 14155 is currently an unassigned port
  @port = port || ENV["YUI_HTTP_PORT"] || 14155
  ENV["YUI_HTTP_PORT"] = @port
end

Given("I start the \"{string}\" application(| on port (\d+))") do |string, _port_str, port|
  set_port(port)

  pending
end

Given("I use an running libyui application (| on port (\d+))") do | _port_str, port|
  set_port(port)
  
  pending
end

# When("I enter {string} into input field {string}") do |string, string2|
#   pending # Write code here that turns the phrase above into concrete actions
# end
