#!/usr/bin/env rspec

require_relative "../../test_helper"
require "y2packager/clients/inst_product_license"

describe Y2Packager::Clients::InstProductLicense do
  subject(:client) { described_class.new }

  let(:dialog) { instance_double(Y2Packager::Dialogs::InstProductLicense, run: :next) }
  let(:product) do
    instance_double(
      Y2Packager::ProductSpec,
      label:                          "SLES",
      license?:                       license?,
      license_confirmation_required?: confirmation_required?,
      license_confirmed?:             license_confirmed?
    )
  end
  let(:other_product) { instance_double(Y2Packager::Product) }
  let(:products) { [product, other_product] }

  let(:license?) { true }
  let(:confirmation_required?) { true }
  let(:license_confirmed?) { false }
  let(:language) { double("Yast::Language", language: "en_US") }
  let(:auto) { false }

  before do
    allow(Y2Packager::Dialogs::InstProductLicense).to receive(:new)
      .and_return(dialog)
    allow(Y2Packager::ProductSpec).to receive(:selected_base).and_return(product)
    allow(Y2Packager::ProductSpec).to receive(:base_products).and_return(products)
    allow(Yast::Mode).to receive(:auto).and_return(auto)
    stub_const("Yast::Language", language)
  end

  describe "#main" do
    it "opens the license dialog with the selected product (without back button)" do
      expect(Yast::GetInstArgs).to receive(:enable_back).and_return(false)
      expect(Y2Packager::Dialogs::InstProductLicense).to receive(:new)
        .with(product, disable_buttons: [:back])
      client.main
    end

    it "opens the license dialog with the selected product (with back button)" do
      expect(Yast::GetInstArgs).to receive(:enable_back).and_return(true)
      expect(Y2Packager::Dialogs::InstProductLicense).to receive(:new)
        .with(product, disable_buttons: [])
      client.main
    end

    context "when the user accepts the license" do
      before do
        allow(dialog).to receive(:run).and_return(:next)
      end

      it "returns :next" do
        expect(client.main).to eq(:next)
      end
    end

    context "when the user clicks the 'Back' button" do
      before do
        allow(dialog).to receive(:run).and_return(:back)
      end

      it "returns :back" do
        expect(client.main).to eq(:back)
      end
    end

    context "when no base product is found" do
      let(:product) { nil }

      it "does not open the license dialog" do
        expect(Y2Packager::Dialogs::InstProductLicense).to_not receive(:new)
          .with(product)
        client.main
      end

      it "returns :auto" do
        expect(client.main).to eq(:auto)
      end
    end

    context "when no license is found for the selected base product" do
      let(:license?) { false }

      it "does not open the license dialog" do
        expect(Y2Packager::Dialogs::InstProductLicense).to_not receive(:new)
          .with(product)
        client.main
      end

      context "and running during normal installation" do
        let(:auto) { false }

        it "returns :auto" do
          expect(client.main).to eq(:auto)
        end
      end

      context "and running during autoinstallation" do
        let(:auto) { true }

        it "returns :next" do
          expect(client.main).to eq(:next)
        end
      end
    end

    context "during normal installation" do
      let(:auto) { false }

      context "when only one base product is found" do
        let(:products) { [product] }

        it "returns :auto" do
          expect(client.main).to eq(:auto)
        end
      end

      context "when more than one product is found" do
        it "opens the license dialog" do
          expect(Y2Packager::Dialogs::InstProductLicense).to receive(:new)
          client.main
        end
      end
    end

    context "during autoinstallation" do
      let(:auto) { true }

      context "when the license has been accepted" do
        let(:license_confirmed?) { true }

        it "returns :next" do
          expect(client.main).to eq(:next)
        end
      end

      context "when the license has not been accepted" do
        let(:license_confirmed?) { false }

        it "opens the license dialog" do
          expect(Y2Packager::Dialogs::InstProductLicense).to receive(:new)
          client.main
        end
      end
    end
  end
end
