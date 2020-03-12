# Copyright (c) [2017-2020] SUSE LLC
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
#
require_relative "../../test_helper"

require "cwm/rspec"
require "y2packager/product_location"
require "y2packager/product_location_details"
require "y2packager/dialogs/addon_selector"

describe Y2Packager::Dialogs::AddonSelector do
  subject { described_class.new(products) }

  include_examples "CWM::Dialog"

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
        depends_on: ["SLE-15-Module-Basesystem 15.0-0"]
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

  describe "#contents" do
    context "during installation" do
      before do
        allow(Yast::Stage).to receive(:initial).and_return(true)
        allow(Yast::Mode).to receive(:installation).and_return(true)
        allow(Yast::UI).to receive(:UserInput).and_return(:next)

        # mock the control.xml default
        allow(Yast::ProductFeatures).to receive(:GetFeature)
          .with("software", "default_modules")
          .and_return(["sle-module-basesystem"])
        allow(Y2Packager::Resolvable).to receive(:find)
          .with(kind: :product, status: :selected)
          .and_return([])
      end

      it "preselects the default products from control.xml" do
        expect(Y2Packager::Widgets::AddonsSelector).to receive(:new)
          .with(anything, [products.first])

        subject.contents
      end
    end
  end

  describe "#abort_handler" do
    it "returns :abort" do
      allow(Yast::Stage).to receive(:initial).and_return(false)
    end

    context "during installation" do
      let(:confirm_abort) { false }

      before do
        allow(Yast::Stage).to receive(:initial).and_return(true)
        allow(Yast::Popup).to receive(:ConfirmAbort).and_return(confirm_abort)
      end

      it "asks for confirmation" do
        expect(Yast::Popup).to receive(:ConfirmAbort).and_return(true)

        subject.abort_handler
      end

      context "when confirmed" do
        let(:confirm_abort) { true }

        it "returns true" do
          expect(subject.abort_handler).to eq(true)
        end
      end

      context "when rejected" do
        let(:confirm_abort) { false }

        it "returns false" do
          expect(subject.abort_handler).to eq(false)
        end
      end
    end
  end

  describe "#next_handler" do
    let(:addons_selector) { Y2Packager::Widgets::AddonsSelector.new(products, []) }

    before do
      allow(Y2Packager::Widgets::AddonsSelector).to receive(:new).and_return(addons_selector)
    end

    context "when a product is selected" do
      before do
        addons_selector.items.each(&:select!)
      end

      it "does not display a popup" do
        expect(Yast::Popup).to_not receive(:ContinueCancel)

        subject.next_handler
      end

      it "returns true" do
        expect(subject.next_handler).to eq(true)
      end
    end

    context "when none product is selected" do
      let(:confirm_continue) { false }

      before do
        addons_selector.items.each(&:unselect!)
        allow(Yast::Popup).to receive(:ContinueCancel).and_return(confirm_continue)
      end

      it "displays a popup asking for confirmation" do
        expect(Yast::Popup).to receive(:ContinueCancel).with(/no product/i)

        subject.next_handler
      end

      context "and the user decides to continue" do
        let(:confirm_continue) { true }

        it "returns true" do
          expect(subject.next_handler).to eq(true)
        end
      end

      context "but the user decides to cancel" do
        let(:confirm_continue) { false }

        it "returns false" do
          expect(subject.next_handler).to eq(false)
        end
      end
    end
  end
end
