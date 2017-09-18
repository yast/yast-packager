#!/usr/bin/env rspec

require_relative "../../test_helper"
require "y2packager/clients/inst_product_license"

describe Y2Packager::Clients::InstProductLicense do
  subject(:client) { described_class.new }

  let(:dialog) { instance_double(Y2Packager::Dialogs::InstProductLicense, run: :next) }
  let(:product) do
    instance_double(
      Y2Packager::Product,
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

  before do
    allow(Y2Packager::Dialogs::InstProductLicense).to receive(:new)
      .and_return(dialog)
    allow(Y2Packager::Product).to receive(:selected_base).and_return(product)
    allow(Y2Packager::Product).to receive(:available_base_products).and_return(products)
  end

  describe "#main" do
    it "opens the license dialog with the selected product" do
      expect(Y2Packager::Dialogs::InstProductLicense).to receive(:new)
        .with(product)
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

    context "when only one base product is found" do
      let(:products) { [product] }

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

      it "returns :auto" do
        expect(client.main).to eq(:auto)
      end
    end
  end
end
