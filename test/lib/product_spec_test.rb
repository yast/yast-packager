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

require_relative "../test_helper"
require "y2packager/product_spec_reader"
require "y2packager/product_spec"

describe Y2Packager::ProductSpec do
  let(:reader) { Y2Packager::ProductSpecReader.new }

  let(:base) do
    Y2Packager::ProductSpec.new(
      name: "SLES", display_name: "SUSE Linux Enterprise Server", order: 1, version: "15.3",
      arch: :x86_64, base: true
    )
  end

  let(:addon) do
    Y2Packager::ProductSpec.new(
      name: "sles-basesystem-module", display_name: "Basesystem Module", order: 2, version: "15.3",
      arch: :x86_64, base: false
    )
  end

  before do
    allow(Y2Packager::ProductSpecReader).to receive(:new).and_return(reader)
    allow(reader).to receive(:products).and_return([base, addon])
  end

  describe ".base_products" do
    it "returns the base products" do
      products = described_class.base_products(force: true)
      expect(products.map(&:name)).to eq(["SLES"])
    end
  end

  describe ".selected_base" do
    before { described_class.reset }

    context "when a product was selected" do
      before { base.select }

      it "returns the selected product" do
        expect(described_class.selected_base).to eq(base)
      end
    end

    context "when there is no base selected product" do
      it "returns nil" do
        expect(described_class.selected_base).to be_nil
      end
    end
  end

  describe ".forced_base_product" do
    let(:select_product) { nil }

    let(:opensuse) do
      instance_double(Y2Packager::ProductSpec, name: "openSUSE")
    end

    let(:sle) do
      instance_double(Y2Packager::ProductSpec, name: "SLE")
    end

    before do
      described_class.reset

      allow(described_class).to receive(:base_products).and_return([opensuse, sle])

      allow(Yast::ProductFeatures).to receive(:GetStringFeature)
        .with("software", "select_product")
        .and_return(select_product)
    end

    context "when the control file is not forcing to select a base product selected" do
      it "returns nil" do
        expect(described_class.forced_base_product).to be_nil
      end
    end

    context "when the control file is not forcing to select a base product selected" do
      context "and the product is available" do
        let(:select_product) { "openSUSE" }

        it "returns the prodcut" do
          expect(described_class.forced_base_product).to eq(opensuse)
        end
      end

      context "but none available base product name match" do
        let(:select_product) { "Whatever product" }

        it "returns nil" do
          expect(described_class.forced_base_product).to be_nil
        end
      end

      context "but is empty" do
        let(:select_product) { "" }

        it "returns nil" do
          expect(described_class.forced_base_product).to be_nil
        end
      end
    end
  end
end
