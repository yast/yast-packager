When(/^I click button(| with ID) "(.*)"$/) do |type, name|
  params = { action: "press_button" }

  if type.empty?
    params[:label] = name
  else
    params[:id] = name
  end

  send_action(params)
end

When(/^I select (?:radiobutton|RadioButton|radio button)(| with ID) "(.*)"$/) do |type, name|
  params = { action: "switch_radio" }

  if type.empty?
    params[:label] = name
  else
    params[:id] = name
  end

  send_action(params)
end

When(/^I enter "(.*)" into input field(| with ID) "(.*)"$/) do |input, type, name|
  params = { action: "enter_text", value: input }
  if type.empty?
    params[:label] = name
  else
    params[:id] = name
  end

  send_action(params)
end

When(/^I set value "(.*)" for (?:combobox|ComboBox|combo box) (with ID |)"(.*)"$/) do |input, type, name|
  params = { action: "select_combo", value: input }
  if type.empty?
    params[:label] = name
  else
    params[:id] = name
  end

  send_action(params)
end
