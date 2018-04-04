#!/usr/bin/env rspec

require_relative "../../test_helper"
require "y2packager/clients/inst_product_upgrade_license"

describe Y2Packager::Clients::InstProductUpgradeLicense do
  describe "#main" do
    let(:language) { double("Yast::Language", language: "en_US") }
    let(:product) { nil }

    before do
      allow(Y2Packager::ProductUpgrade).to receive(:new_base_product).and_return(product)
      allow(Yast::Report).to receive(:Error)
      allow(Yast::GetInstArgs).to receive(:going_back).and_return(false)
      stub_const("Yast::Language", language)
    end

    context "going back in the workflow" do
      before do
        expect(Yast::GetInstArgs).to receive(:going_back).and_return(true)
      end

      it "returns :back" do
        expect(subject.main).to eq(:back)
      end

      it "does not display the license" do
        expect_any_instance_of(Y2Packager::Dialogs::InstProductLicense).to_not receive(:run)
        subject.main
      end
    end

    context "no product found" do
      it "displays an error popup" do
        expect(Yast::Report).to receive(:Error).with(/Cannot find any product to upgrade/)
        subject.main
      end

      it "returns :back" do
        expect(subject.main).to eq(:back)
      end
    end

    context "base product found" do
      let(:product) do
        instance_double(
          Y2Packager::Product,
          label:              "SLES",
          license?:           true,
          license_confirmed?: false
        )
      end

      it "returns :auto if no product license is found" do
        expect(product).to receive(:license?).at_least(:once).and_return(false)
        expect(subject.main).to eq(:auto)
      end

      it "displays the product license" do
        allow(Yast::Language).to receive(:language).and_return("en_US")
        expect_any_instance_of(Y2Packager::Dialogs::InstProductLicense).to receive(:run)
        subject.main
      end
    end
  end
end
