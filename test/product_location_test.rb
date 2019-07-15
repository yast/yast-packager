#! /usr/bin/env rspec

require_relative "./test_helper"
require "uri"

require "y2packager/product_location"

# a helper method, find a specified product in the list
def find_product(arr, product)
  arr.find { |p| p.details.product == product }
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
      expect(scan_result.map { |p| p.details.product }).to match_array(
        ["SLES", "sle-module-basesystem", "sle-module-server-applications"]
      )
    end

    it "reads the product descriptions" do
      base_module = find_product(scan_result, "sle-module-basesystem")
      expect(base_module.details.description).to include("SUSE Linux Enterprise Basesystem Module")
    end

    it "finds the base products" do
      base_products = scan_result.select { |p| p.details.base }
      # there is only the SLES base product in the testing repository
      expect(base_products.map { |p| p.details.product }).to eq(["SLES"])
    end

    it "finds the modules/extensions" do
      modules = scan_result.reject { |p| p.details.base }
      # there are 2 modules in the testing repository
      expect(modules.map { |p| p.details.product }).to match_array(
        ["sle-module-basesystem", "sle-module-server-applications"]
      )
    end

    it "finds the dependencies" do
      sles = find_product(scan_result, "SLES")
      base_module = find_product(scan_result, "sle-module-basesystem")
      server_module = find_product(scan_result, "sle-module-server-applications")

      expect(sles.details.depends_on).to eq([])
      expect(base_module.details.depends_on).to eq(["/Product-SLES"])
      expect(server_module.details.depends_on).to match_array(
        ["/Module-Basesystem", "/Product-SLES"]
      )
    end
  end
end
