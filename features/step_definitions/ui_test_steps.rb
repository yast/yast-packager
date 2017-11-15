require "json"
require "net/http"
require "uri"
require "timeout"
require "socket"

def send_request(method, path, params = {})
  uri = URI("http://#{@app_host}:#{@app_port}")
  uri.path = path
  uri.query = URI.encode_www_form(params)

  if (method == :get)
    res = Net::HTTP.get_response(uri)
  elsif (method == :post)
    # a trick how to add query parameters to a POST request,
    # usall Net::HTTP.post(uri, data) does not allow using query
    req = Net::HTTP::Post.new("#{uri.path}?#{uri.query}")
    http = Net::HTTP.new(uri.host, uri.port)
    res = http.request(req)
  else
    raise "Unknown HTTP method: #{method.inspect}"
  end

  if res.is_a?(Net::HTTPSuccess)
    res.body.empty? ? nil : JSON.parse(res.body)
  elsif res.is_a?(Net::HTTPNotFound)
    raise "Widget not found"
  else
    raise "Unknown error"
  end
end

def read_widgets(type: nil, label:nil, id: nil)
  params = {}
  params[:id] = id if id
  params[:label] = label if label
  params[:type] = type if type

  send_request(:get, "/widgets", params)
end

def read_widget(type: nil, label:nil, id: nil)
  read_widgets(type: type, label: label, id: id).first
end

def send_action(action: nil, type: nil, label:nil, id: nil, value: nil)
  params = {}
  params[:action] = action if action
  params[:id] = id if id
  params[:label] = label if label
  params[:type] = type if type
  params[:value] = value if value

  send_request(:post, "/widgets", params)
end

Then(/^the dialog heading should be "(.*)"(?: in (\d+) seconds)?$/) do |heading, seconds|
  Timeout.timeout(seconds || DEFAULT_TIMEOUT) do
    loop do
      break if heading == read_widget(type: "YWizard")["debug_label"]
      sleep(1)
    end
  end
end

