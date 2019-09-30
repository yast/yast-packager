#!/usr/bin/env rspec

require_relative "../../test_helper"
require "y2packager/clients/inst_repositories_initialization"

describe Y2Packager::Clients::InstRepositoriesInitialization do
  subject(:client) { described_class.new }

  let(:success) { true }
  let(:prod1) { instance_double(Y2Packager::Product, name: "Prod1", select: nil) }
  let(:prod2) { instance_double(Y2Packager::Product, name: "Prod2", select: nil) }
  let(:products) { [prod1] }

  describe "#main" do
    before do
      allow(Yast::Packages).to receive(:InitializeCatalogs)
      allow(Yast::Packages).to receive(:InitializeAddOnProducts)
      allow(Yast::Packages).to receive(:InitFailed).and_return(!success)
      allow(Y2Packager::Product).to receive(:forced_base_product)
      allow(Y2Packager::Product).to receive(:available_base_products).and_return(products)
      allow(Y2Packager::SelfUpdateAddonRepo).to receive(:present?).and_return(false)
      allow(Y2Packager::MediumType).to receive(:online?).and_return(false)
      allow(Y2Packager::MediumType).to receive(:offline?).and_return(false)
    end

    it "initializes Packages subsystem" do
      expect(Yast::Packages).to receive(:InitializeCatalogs)
      client.main
    end

    it "returns :next" do
      expect(client.main).to eq(:next)
    end

    it "adds the self update repo if it is present" do
      expect(Y2Packager::SelfUpdateAddonRepo).to receive(:present?).and_return(true)
      expect(Y2Packager::SelfUpdateAddonRepo).to receive(:create_repo)
      client.main
    end

    it "does not add the self update repo if it is missing" do
      expect(Y2Packager::SelfUpdateAddonRepo).to receive(:present?).and_return(false)
      expect(Y2Packager::SelfUpdateAddonRepo).to_not receive(:create_repo)
      client.main
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
      let(:products) { [prod1] }

      it "selects the product for installation" do
        expect(prod1).to receive(:select)
        client.main
      end
    end

    context "when a product is forced to be used" do
      let(:products) { [prod1, prod2] }

      before do
        allow(Y2Packager::Product).to receive(:forced_base_product).and_return(prod2)
      end

      it "selects the product for installation" do
        expect(prod2).to receive(:select)
        client.main
      end
    end

    context "when more than one product is available" do
      let(:products) { [prod1, prod2] }

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
