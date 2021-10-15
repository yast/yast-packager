# This is a testing client for the addon product dialog which is displayed
# after adding a multi-repository medium.
#
# Run it using "yast2 ./test_addon_selector.rb" command

require "y2packager/repo_product_spec"
require "y2packager/dialogs/addon_selector"

new_repos = [
  ["sle-basesystem-module", "Basesystem Module", "Basesystem-Module 15-0", "/Basesystem"],
  ["sle-desktop-applications-module", "Desktop Applications Module", "Desktop-Applications-Module 15-0", "/Desktop-Applications"],
  ["sle-desktop-productivity-module", "Desktop Productivity Module", "Desktop-Productivity-Module 15-0", "/Desktop-Productivity"],
  ["sle-development-module", "Development Tools Module", "Development-Tools-Module 15-0", "/Development-Tools"],
  ["sle-ha-module", "High Availability Module", "HA-Module 15-0", "/HA"],
  ["sle-hpc-module", "High Performance Computing Module", "HPC-Module 15-0", "/HPC"],
  ["sle-legacy-module", "Legacy Module", "Legacy-Module 15-0", "/Legacy"],
  ["sle-public-cloud-module", "Public Cloud Module", "Public-Cloud-Module 15-0", "/Public-Cloud"],
  ["sle-sap-applications-module", "SAP Applications Module", "SAP-Applications-Module 15-0", "/SAP-Applications"],
  ["sle-scripting-module", "Scripting Module", "Scripting-Module 15-0", "/Scripting"],
  ["sle-server-applications-module", "Server Applications Module", "Server-Applications-Module 15-0", "/Server-Applications"]
]

puts "Repositories to select: " + new_repos.inspect

products = new_repos.map do |name, display_name, media_name, dir|
  Y2Packager::RepoProductSpec.new(
    name: name, display_name: display_name, media_name: display_name, dir: dir, base: false
  )
end
dialog = Y2Packager::Dialogs::AddonSelector.new(products)

puts "Dialog result: " + dialog.run.inspect
puts "Selected products: " + dialog.selected_products.inspect
