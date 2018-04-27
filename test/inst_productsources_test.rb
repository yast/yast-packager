#!/usr/bin/env rspec

require_relative "test_helper"
require "y2packager/pkg_helpers"
Yast.import "Sequencer"
Yast.import "Mode"

describe "Yast::InstProductSourcesClient" do
  subject(:client) do
    # postpone loading the client as much as possible
    require_relative "../src/clients/inst_productsources"
    Yast::InstProductsourcesClient.new
  end

  before do
    allow(Yast::Language).to receive(:language).and_return("en_US")
    allow(Yast::Mode).to receive(:normal).and_return(false)
    allow(Yast::Sequencer).to receive(:Run).and_return(true)
  end

  describe "#CreateSource" do
    let(:url) { "http://download.opensuse.org/$releasever/repo/oss/" }
    let(:pth) { "/product" }
    let(:name) { "Main (OSS)" }

    it "probes and adds the repository" do
      expect(Y2Packager::PkgHelpers).to receive(:repository_probe)
        .with(url, pth).and_return("YUM")
      expect(Y2Packager::PkgHelpers).to receive(:repository_add)
        .with(hash_including("base_urls" => [url]))
      client.CreateSource(url, pth, name, nil, nil, nil)
    end

    context "when the repo was not detected" do
      before do
        allow(Y2Packager::PkgHelpers).to receive(:repository_probe)
          .and_return("NONE")
      end

      it "does not adds the repository" do
        expect(Y2Packager::PkgHelpers).to_not receive(:repository_add)
        client.CreateSource(url, pth, name, nil, nil, nil)
      end
    end
  end
end
