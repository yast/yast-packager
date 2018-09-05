#!/usr/bin/env rspec

__END__

require_relative "../../test_helper"
require "y2packager/clients/inst_repositories_initialization"

describe Y2Packager::Clients::InstRepositoriesInitialization do
  subject(:client) { described_class.new }

  let(:success) { true }
  let(:prod1) { instance_double(Y2Packager::Product, select: nil) }
  let(:prod2) { instance_double(Y2Packager::Product, select: nil) }
  let(:products) { [prod1] }

  describe "#main" do
    before do
      allow(Yast::Packages).to receive(:InitializeCatalogs)
      allow(Yast::Packages).to receive(:InitializeAddOnProducts)
      allow(Yast::Packages).to receive(:InitFailed).and_return(!success)
      allow(Y2Packager::Product).to receive(:available_base_products).and_return(products)
    end

    it "initializes Packages subsystem" do
      expect(Yast::Packages).to receive(:InitializeCatalogs)
      client.main
    end

    it "returns :next" do
      expect(client.main).to eq(:next)
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
