#!/usr/bin/env rspec

require_relative "../../test_helper"
require "y2packager/clients/inst_repositories_initialization"

describe Y2Packager::Clients::InstRepositoriesInitialization do
  subject(:client) { described_class.new }

  let(:success) { true }
  let(:prod1_spec) { instance_double(Y2Packager::ProductSpec, name: "Prod1", to_product: prod1) }
  let(:prod2_spec) { instance_double(Y2Packager::ProductSpec, name: "Prod2", to_product: prod2) }
  let(:prod1) { instance_double(Y2Packager::Product, name: "Prod1", select: nil) }
  let(:prod2) { instance_double(Y2Packager::Product, name: "Prod2", select: nil) }
  let(:products) { [prod1_spec] }

  describe "#main" do
    before do
      allow(Yast::Packages).to receive(:InitializeCatalogs)
      allow(Yast::Packages).to receive(:InitializeAddOnProducts)
      allow(Yast::Packages).to receive(:InitFailed).and_return(!success)
      allow(Y2Packager::ProductSpec).to receive(:forced_base_product)
      allow(Y2Packager::ProductSpec).to receive(:base_products).and_return(products)
      allow(Y2Packager::SelfUpdateAddonRepo).to receive(:present?).and_return(false)
      allow(Y2Packager::MediumType).to receive(:online?).and_return(false)
      allow(Y2Packager::MediumType).to receive(:offline?).and_return(false)
      allow(Yast::GetInstArgs).to receive(:going_back).and_return(false)
    end

    it "initializes Packages subsystem" do
      expect(Yast::Packages).to receive(:InitializeCatalogs)
      client.main
    end

    it "returns :next" do
      expect(client.main).to eq(:next)
    end

    context "going back" do
      before do
        allow(Yast::GetInstArgs).to receive(:going_back).and_return(true)
      end

      it "does not initialize Packages subsystem" do
        expect(Yast::Packages).to_not receive(:InitializeCatalogs)
        client.main
      end

      it "returns :back" do
        expect(client.main).to eq(:back)
      end
    end

    context "when initialization fails" do
      let(:success) { false }

      it "returns :abort" do
        expect(client.main).to eq(:abort)
      end

      it "shows an error" do
        expect(Yast::Popup).to receive(:Error)
        client.main
      end
    end

    context "when only one product is available" do
      let(:products) { [prod1_spec] }

      it "selects the product for installation" do
        expect(prod1).to receive(:select)
        client.main
      end
    end

    context "when a product is forced to be used" do
      let(:products) { [prod1_spec, prod2_spec] }

      before do
        allow(Y2Packager::ProductSpec).to receive(:forced_base_product).and_return(prod2_spec)
      end

      it "selects the product for installation" do
        expect(prod2).to receive(:select)
        client.main
      end
    end

    context "when more than one product is available" do
      let(:products) { [prod1_spec, prod2_spec] }

      it "unselects all products" do
        expect(prod1).to receive(:restore)
        expect(prod2).to receive(:restore)
        client.main
      end
    end

    context "when no products are found" do
      let(:products) { [] }

      it "returns :abort" do
        expect(client.main).to eq(:abort)
      end

      it "shows an error" do
        expect(Yast::Popup).to receive(:Error)
        client.main
      end
    end
  end
end
