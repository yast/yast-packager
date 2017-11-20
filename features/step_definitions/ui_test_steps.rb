require "json"
require "net/http"
require "uri"
require "timeout"
require "socket"

def send_request(method, path, params = {})
  uri = URI("http://#{@app_host}:#{@app_port}")
  uri.path = path
  uri.query = URI.encode_www_form(params)

  if method == :get
    res = Net::HTTP.get_response(uri)
  elsif method == :post
    # a trick how to add query parameters to a POST request,
    # the usuall Net::HTTP.post(uri, data) does not allow using a query
    req = Net::HTTP::Post.new("#{uri.path}?#{uri.query}")
    http = Net::HTTP.new(uri.host, uri.port)
    res = http.request(req)
  else
    raise "Unknown HTTP method: #{method.inspect}"
  end

  puts "Response (#{res.code}:#{res.message}): #{res.body}" if ENV["DEBUG"]
  if res.is_a?(Net::HTTPSuccess)
    res.body.empty? ? nil : JSON.parse(res.body)
  elsif res.is_a?(Net::HTTPNotFound)
    raise "Widget not found"
  else
    raise "Error code: #{res.code} #{res.message}"
  end
end

def read_widgets(type: nil, label: nil, id: nil)
  params = {}
  params[:id] = id if id
  params[:label] = label if label
  params[:type] = type if type

  send_request(:get, "/widgets", params)
end

def read_widget(type: nil, label: nil, id: nil)
  read_widgets(type: type, label: label, id: id).first
end

def send_action(action: nil, type: nil, label: nil, id: nil, value: nil)
  params = {}
  params[:action] = action if action
  params[:id] = id if id
  params[:label] = label if label
  params[:type] = type if type
  params[:value] = value if value

  send_request(:post, "/widgets", params)
end

def with_label(widgets, label)
  widgets.select { |w| w["debug_label"] == label || w["label"] == label }
end

def including_label(widgets, label)
  widgets.select { |w| w["debug_label"].include?(label) || w["label"].include?(label) }
end

def matching_label(widgets, rexp)
  regexp = Regexp.new(rexp)
  widgets.select { |w| regexp.match(w["debug_label"]) || regexp.match(w["label"]) }
end

def timed_retry(seconds, &block)
  timeout = seconds.to_i
  timeout = DEFAULT_TIMEOUT if timeout == 0

  Timeout.timeout(timeout) do
    loop do
      break if block.call
      puts "Retrying..." if ENV["DEBUG"]
      sleep(1)
    end
  end
end

WIDGET_MAPPING = {
  "label" => "YLabel",
  "checkbox" => "YCheckBox",
  "check box" => "YCheckBox",
  "radiobutton" => "YRadioButton",
  "radio button" => "YRadioButton",
  "pushbutton" => "YPushButton",
  "push button" => "YPushButton",
  "button" => "YPushButton",
}

TIMEOUT_REGEXP = "(?: in (\\d+) seconds)?"

WIDGET_REGEXP = "(widget|label|check(?: )?box|radio(?: )?button|(?:push(?: )?)?button) "

Then(/^the dialog heading should be "(.*)"#{TIMEOUT_REGEXP}$/) do |heading, seconds|
  timed_retry(seconds) do
    # FIXME: non-wizard windows use "Heading" widget:
    # test case:
    # read_widget(type: "YLabel_Heading")["debug_label"] == heading
    read_widget(type: "YWizard")["debug_label"] == heading
  end
end

Then(/^(?:a |the )?#{WIDGET_REGEXP}(?:having )?(matching |including |)"(.*)"(label )? should be displayed#{TIMEOUT_REGEXP}$/) \
do |type, match, label, label_type, seconds|
  timed_retry(seconds) do
    widgets = read_widgets(type: WIDGET_MAPPING[type])

    case match
    when ""
      !with_label(widgets, label).empty?
    when "matching "
      !matching_label(widgets, label).empty?
    when "including "
      !including_label(widgets, label).empty?
    end
  end
end

Then(/^(?:a )popup should be displayed#{TIMEOUT_REGEXP}$/) do |seconds|
  timed_retry(seconds) do
    read_widget(type: "YDialog")["type"] == "popup"
  end
end
