#! /usr/bin/env rspec

require_relative "./test_helper"
require "uri"

require "y2packager/product_location"

# a helper method, find a specified product in the list
def find_product(arr, product)
  arr.find { |p| p.product_name == product }
end

# loading all repositories and evaluating the product dependencies
# using the solver takes some time, run it only once and cache
# the result for all tests
dir = File.join(__dir__, "data/zypp/test_offline_repo")
repo_url = "dir://#{URI.escape(dir)}"
scan_result = Y2Packager::ProductLocation.scan(repo_url)

describe Y2Packager::ProductLocation do
  describe ".scan" do
    it "finds all product repositories" do
      # there are 3 testing product repositories
      expect(scan_result.size).to eq(3)
      # match_array ignores the order of the items
      expect(scan_result.map(&:product_name)).to match_array(
        ["SLES", "sle-module-basesystem", "sle-module-server-applications"]
      )
    end

    it "reads the product descriptions" do
      base_module = find_product(scan_result, "sle-module-basesystem")
      expect(base_module.description).to include("SUSE Linux Enterprise Basesystem Module")
    end

    it "finds the base products" do
      base_products = scan_result.select(&:base)
      # there is only the SLES base product in the testing repository
      expect(base_products.map(&:product_name)).to eq(["SLES"])
    end

    it "finds the modules/extensions" do
      modules = scan_result.reject(&:base)
      # there are 2 modules in the testing repository
      expect(modules.map(&:product_name)).to match_array(
        ["sle-module-basesystem", "sle-module-server-applications"]
      )
    end

    it "finds the dependencies" do
      sles = find_product(scan_result, "SLES")
      base_module = find_product(scan_result, "sle-module-basesystem")
      server_module = find_product(scan_result, "sle-module-server-applications")

      expect(sles.depends_on).to eq([])
      expect(base_module.depends_on).to eq(["/Product-SLES"])
      expect(server_module.depends_on).to match_array(
        ["/Module-Basesystem", "/Product-SLES"]
      )
    end
  end
end
