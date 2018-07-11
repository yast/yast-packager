When(/^I click button "(.*)"$/) do |label|
  send_action(action: "press_button", type: "YPushButton", label: label)
end

When(/^I enter "(.*)" into input field(| with ID) "(.*)"$/) do |input, type, name|
  params = { action: "enter_text", value: input, type: "YInputField" }
  if type.empty?
    params[:label] = name
  else
    params[:id] = name
  end

  send_action(params)
end
