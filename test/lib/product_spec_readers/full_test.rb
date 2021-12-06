# Copyright (c) [2021] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require_relative "../../test_helper"
require "cgi"
require "y2packager/product_spec_readers/full"

describe Y2Packager::ProductSpecReaders::Full do
  subject(:reader) { described_class.new }

  # a helper method, find a specified product in the list
  def find_product(arr, product)
    arr.find { |p| p.name == product }
  end

  ESCAPED_DATA_PATH = DATA_PATH.to_s.split("/").map {|d| CGI.escape(d)}.join("/").freeze
  # URL of the local testing repository
  REPO_URL = "dir://#{File.join(ESCAPED_DATA_PATH, "zypp/test_offline_repo")}".freeze

  before do
    # the testing repository only contains the x86_64 packages/products
    # and the solver ignores the packages for incompatible architectures,
    # that means the test would fail anywhere except on x86_64.
    #
    # So we modify the "setarch" call to always pass the "x86_64" parameter.
    allow_any_instance_of(::Solv::Pool).to receive(:setarch)
      .and_wrap_original do |method, *_args|
        method.call("x86_64")
      end
  end

  describe ".scan" do
    let(:scan_result) { reader.products(REPO_URL) }

    it "finds all product repositories" do
      # there are 3 testing product repositories
      expect(scan_result.size).to eq(3)
      # match_array ignores the order of the items
      expect(scan_result.map(&:name)).to match_array(
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
      expect(base_products.map(&:name)).to eq(["SLES"])
    end

    it "finds the modules/extensions" do
      modules = scan_result.reject(&:base)
      # there are 2 modules in the testing repository
      expect(modules.map(&:name)).to match_array(
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

    it "return empty list when there is only one repository" do
      expect(Yast::Pkg).to receive(:RepositoryScan).and_return([["/", "Foo product"]])
      expect(reader.products(REPO_URL)).to eq([])
    end

    it "return empty list when there is none repository found" do
      expect(Yast::Pkg).to receive(:RepositoryScan).and_return([])
      expect(reader.products(REPO_URL)).to eq([])
    end
  end
end
