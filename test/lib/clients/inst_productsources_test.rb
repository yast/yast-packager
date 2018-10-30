#!/usr/bin/env rspec

require_relative "../../test_helper"
require "y2packager/clients/inst_productsources"

describe Yast::InstProductsourcesClient do
  subject(:client) { described_class.new }

  describe "#main" do
    before do
      allow(Yast::Sequencer).to receive(:Run)
      allow(Yast::Wizard).to receive(:OpenDialog)
      allow(Yast::Wizard).to receive(:CloseDialog)
    end

    it "returns :auto if AddOnProduct is set to skip" do
      allow(Yast::AddOnProduct).to receive(:skip_add_ons).and_return(true)

      expect(client.main).to eq :auto
    end

    it "returns :back if going back" do
      allow(Yast::GetInstArgs).to receive(:going_back).and_return(true)

      expect(client.main).to eq :back
    end

    context "run as command line" do
      before do
        allow(Yast::Mode).to receive(:normal).and_return(true)
        allow(Yast::WFM).to receive(:Args).and_return("help")
        allow(Yast::CommandLine).to receive(:Run)
      end

      it "runs command line" do
        expect(Yast::CommandLine).to receive(:Run)

        client.main
      end

      it "returns auto" do
        expect(client.main).to eq :auto
      end
    end

    it "opens wizard in normal mode" do
      expect(Yast::Wizard).to receive(:OpenDialog)
      expect(Yast::Wizard).to receive(:CloseDialog)

      allow(Yast::Mode).to receive(:normal).and_return(true)

      client.main
    end
  end
end
