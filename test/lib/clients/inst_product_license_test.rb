#!/usr/bin/env rspec

require_relative "../../test_helper"
require "y2packager/clients/inst_product_license"

describe Y2Packager::Clients::InstProductLicense do
  subject(:client) { described_class.new }

  let(:dialog) { instance_double(Y2Packager::Dialogs::InstProductLicense, run: :next) }
  let(:product) { instance_double(Y2Packager::Product, license?: license?) }
  let(:license?) { true }

  before do
    allow(Y2Packager::Dialogs::InstProductLicense).to receive(:new)
      .and_return(dialog)
    allow(Y2Packager::Product).to receive(:selected_base).and_return(product)
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

    context "when no license is found for the selected base product" do
      let(:license?) { false }

      it "does not open the license dialog" do
        expect(Y2Packager::Dialogs::InstProductLicense).to_not receive(:new)
          .with(product)
        client.main
      end

      it "returns :next" do
        expect(client.main).to eq(:next)
      end
    end
  end
end
