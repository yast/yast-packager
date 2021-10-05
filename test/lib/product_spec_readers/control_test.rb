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
require "y2packager/product_spec_readers/control"

describe Y2Packager::ProductSpecReaders::Control do
  subject(:reader) { described_class.new }

  let(:product_data) do
    {
      "display_name"    => "SUSE Linux Enterprise Server 15 SP2",
      "name"            => "SLES",
      "version"         => "15.2",
      "register_target" => "sle-15-$arch"
    }
  end

  describe "#products" do
    before do
      allow(Yast::Linuxrc).to receive(:InstallInf).with("specialproduct").and_return("")
      allow(Yast::ProductFeatures).to receive(:GetFeature)
        .with("software", "base_products").and_return([])
      allow(Yast::Arch).to receive(:architecture).and_return("x86_64")
    end

    after do
      # the read products are cached, we need to reset them manually for the next test
      described_class.instance_variable_set(:@products, nil)
    end

    it "reads the products from the control.xml" do
      expect(Yast::ProductFeatures).to receive(:GetFeature)
        .with("software", "base_products").and_return([product_data])

      products = reader.products
      expect(products).to_not be_empty
      expect(products.first).to be_a(Y2Packager::ControlProductSpec)
      expect(products.first.name).to eq("SLES")
    end

    it "ignores the hidden products" do
      data = product_data.merge("special_product" => true)
      expect(Yast::ProductFeatures).to receive(:GetFeature)
        .with("software", "base_products").and_return([data])

      products = reader.products
      expect(products).to be_empty
    end

    it "ignores the products for incompatible archs" do
      data = product_data.merge("archs" => "aarch64")
      expect(Yast::ProductFeatures).to receive(:GetFeature)
        .with("software", "base_products").and_return([data])

      products = reader.products
      expect(products).to be_empty
    end

    it "expands the $arch variable in the register_target value" do
      expect(Yast::ProductFeatures).to receive(:GetFeature)
        .with("software", "base_products").and_return([product_data])

      product = reader.products.first
      expect(product.register_target).to eq("sle-15-x86_64")
    end

    it "returns empty list if the control file value is missing" do
      # when the value is not found ProductFeatures return empty string!
      expect(Yast::ProductFeatures).to receive(:GetFeature)
        .with("software", "base_products").and_return("")

      products = reader.products
      expect(products).to be_empty
    end
  end
end
