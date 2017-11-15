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

def read_widget(type: nil, label:nil, id: nil)
  widgets = read_widgets(type: type, label: label, id: id)
  widgets.first
end

Then("the dialog heading should be {string}") do |heading|
  expect(read_widget(type: "YWizard")["debug_label"]).to eq(heading)
end

