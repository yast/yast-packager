# Copyright (c) [2020] SUSE LLC
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

require "cwm/rspec"
require "y2packager/product_location"
require "y2packager/product_location_details"
require "y2packager/widgets/addons_selector"

describe Y2Packager::Widgets::AddonsSelector do
  subject(:addons_selector) { described_class.new(products, preselected_products) }

  include_examples "CWM::CustomWidget"

  let(:details_area) do
    subject.contents.nested_find { |i| i.is_a?(CWM::RichText) && i.widget_id == "details_area" }
  end

  let(:basesystem) do
    Y2Packager::ProductLocation.new(
      "SLE-15-Module-Basesystem 15.0-0",
      "/Basesystem",
      product: Y2Packager::ProductLocationDetails.new(product: "sle-module-basesystem")
    )
  end

  let(:desktop_applications) do
    Y2Packager::ProductLocation.new(
      "Desktop-Applications-Module 15-0",
      "/Desktop-Applications",
      product: Y2Packager::ProductLocationDetails.new(
        depends_on: ["/Basesystem"]
      )
    )
  end

  let(:legacy_product) do
    Y2Packager::ProductLocation.new(
      "SLE-15-Module-Legacy 15.0-0",
      "/Legacy",
      product: Y2Packager::ProductLocationDetails.new(product: "sle-module-legacy")
    )
  end

  let(:products) { [basesystem, desktop_applications, legacy_product] }
  let(:preselected_products) { [legacy_product] }

  describe "#initialize" do
    it "selects preselected products" do
      expect(subject.selected_items.map(&:id)).to eq(preselected_products.map(&:dir))
    end
  end

  describe "#items" do
    it "returns a collection of items representing available products" do
      expect(subject.items.map(&:id)).to eq(products.map(&:dir))
    end
  end

  describe "#toggle" do
    let(:item) { subject.items.first }

    it "toggles given item" do
      expect(item).to receive(:toggle)

      subject.toggle(item)
    end

    it "displays the item details" do
      expect(details_area).to receive(:value=).with(item.description)

      subject.toggle(item)
    end

    context "when selected item has dependencies" do
      let(:basesystem_item) { subject.items.find { |i| i.id == "/Basesystem" } }
      let(:desktop_apps_item) { subject.items.find { |i| i.id == "/Desktop-Applications" } }

      context "and they are not selected yet" do
        it "auto-selects them" do
          expect(basesystem_item).to receive(:auto_select!)

          subject.toggle(desktop_apps_item)
        end
      end

      context "but they are already selected" do
        before do
          basesystem_item.select!
        end

        it "does nothing" do
          expect(basesystem_item).to_not receive(:auto_select!)
          expect(basesystem_item).to_not receive(:unselect!)
          expect(basesystem_item).to_not receive(:select!)

          subject.toggle(desktop_apps_item)
        end
      end
    end
  end
end

describe Y2Packager::Widgets::AddonsSelector::Item do
  subject(:item) { described_class.new(product, dependencies, selected) }

  let(:product) do
    Y2Packager::ProductLocation.new(
      "SLE-15-Module-Basesystem 15.0-0",
      "/Basesystem",
      product: Y2Packager::ProductLocationDetails.new(product: "sle-module-basesystem")
    )
  end

  let(:dependencies) { nil }
  let(:selected) { false }

  describe "#id" do
    it "returns a String" do
      expect(subject.id).to be_a(String)
    end

    it "returns the product dir" do
      expect(subject.id).to eq(product.dir)
    end
  end

  describe "#label" do
    let(:product_summary) { "A product summary" }
    let(:product_name) { "A product name" }

    before do
      allow(product).to receive(:summary).and_return(product_summary)
      allow(product).to receive(:name).and_return(product_name)
    end

    it "returns a String" do
      expect(subject.id).to be_a(String)
    end

    context "when product has a summary" do
      it "returns the product summary" do
        expect(subject.label).to eq(product_summary)
      end
    end

    context "when product has not a summary" do
      let(:product_summary) { nil }

      it "returns the product name" do
        expect(subject.label).to eq(product_name)
      end
    end
  end
end
