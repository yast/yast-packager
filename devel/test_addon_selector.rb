# This is a testing client for the addon product dialog which is displayed
# after adding a multi-repository medium.
#
# Run it using "yast2 ./test_addon_selector.rb" command

require "y2packager/product_location"
require "y2packager/dialogs/addon_selector"

new_repos = [
  ["Basesystem-Module 15-0", "/Basesystem"],
  ["Desktop-Applications-Module 15-0", "/Desktop-Applications"],
  ["Desktop-Productivity-Module 15-0", "/Desktop-Productivity"],
  ["Development-Tools-Module 15-0", "/Development-Tools"],
  ["HA-Module 15-0", "/HA"],
  ["HPC-Module 15-0", "/HPC"],
  ["Legacy-Module 15-0", "/Legacy"],
  ["Public-Cloud-Module 15-0", "/Public-Cloud"],
  ["SAP-Applications-Module 15-0", "/SAP-Applications"],
  ["Scripting-Module 15-0", "/Scripting"],
  ["Server-Applications-Module 15-0", "/Server-Applications"]
]

puts "Repositories to select: " + new_repos.inspect

products = new_repos.map { |r| Y2Packager::ProductLocation.new(r[0], r[1]) }
dialog = Y2Packager::Dialogs::AddonSelector.new(products)

puts "Dialog result: " + dialog.run.inspect
puts "Selected products: " + dialog.selected_products.inspect
