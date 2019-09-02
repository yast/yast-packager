require_relative "test_helper"
require "y2packager/medium_type"

describe Y2Packager::MediumType do
  let(:repo_url) { "http://example.com/repo" }

  before do
    allow(Yast::InstURL).to receive(:installInf2Url).and_return(repo_url)
  end

  after do
    # the computed value is cached, we need to reset it manually for the next test
    described_class.instance_variable_set(:@type, nil)
  end

  describe "#type" do
    it "raises an exception when the installation URL is nil" do
      expect(Yast::InstURL).to receive(:installInf2Url).and_return(nil)
      expect { described_class.type }.to raise_exception(/The installation URL is not set/)
    end

    it "raises an exception when the installation URL is empty" do
      expect(Yast::InstURL).to receive(:installInf2Url).and_return("")
      expect { described_class.type }.to raise_exception(/The installation URL is not set/)
    end

    it "returns :online if no repository is found on the medium" do
      expect_any_instance_of(Y2Packager::RepomdDownloader)
        .to receive(:product_repos).and_return([])

      expect(described_class.type).to eq(:online)
    end

    it "returns :offline if at least two repositories are found on the medium" do
      expect_any_instance_of(Y2Packager::RepomdDownloader)
        .to receive(:product_repos).and_return(
          [
            ["Basesystem-Module 15.1-0", "/Module-Basesystem"],
            ["SLES15-SP1 15.1-0", "/Product-SLES"]
          ]
        )

      expect(described_class.type).to eq(:offline)
    end

    context "only one repository on the installation medium" do
      before do
        expect_any_instance_of(Y2Packager::RepomdDownloader)
          .to receive(:product_repos).and_return(
            [
              ["SLES15-SP1 15.1-0", "/"]
            ]
          )
      end

      it "returns :online if the repository does not contain any base product" do
        expect(Y2Packager::ProductLocation).to receive(:scan).and_return([])
        expect(described_class.type).to eq(:online)
      end

      it "returns :standard if the repository contains any base product" do
        details = Y2Packager::ProductLocationDetails.new(
          product:         "SLES",
          summary:         "SUSE Linux Enterprise Server 15 SP1",
          description:     "SUSE Linux Enterprise offers a comprehensive...",
          order:           200,
          base:            true,
          depends_on:      [],
          product_package: "sles-release"
        )
        prod = Y2Packager::ProductLocation.new("/", "/", product: details)

        expect(Y2Packager::ProductLocation).to receive(:scan).and_return([prod])
        expect(described_class.type).to eq(:standard)
      end
    end
  end
end
