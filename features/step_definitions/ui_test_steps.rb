
Then("the dialog heading should be {string}") do |heading|
  puts "Testing heading: #{heading}"
  # read_dialog_heading
  expect(read_dialog_heading).to eq(heading)
end

