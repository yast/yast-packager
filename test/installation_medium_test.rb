require_relative "test_helper"
require "y2packager/installation_medium"

describe Y2Packager::InstallationMedium do
  let(:repo_url) { "http://example.com/repo" }
  let(:products_reader) do
    instance_double(Y2Packager::ProductSpecReaders::Full, products: [])
  end

  before do
    allow(Yast::InstURL).to receive(:installInf2Url).and_return(repo_url)

    allow_any_instance_of(Y2Packager::RepomdDownloader)
      .to receive(:product_repos).and_return([])

    allow(Y2Packager::ProductSpecReaders::Full).to receive(:new).and_return(products_reader)
  end

  after do
    # the computed value is cached, we need to reset it manually for the next test
    described_class.instance_variable_set(:@repo, nil)
    described_class.instance_variable_set(:@multi_repo, nil)
  end

  shared_examples(:check_inst_url) do |method|
    it "raises an exception when the installation URL is nil" do
      expect(Yast::InstURL).to receive(:installInf2Url).and_return(nil)
      expect { described_class.public_send(method) }.to(
        raise_exception(/The installation URL is not set/)
      )
    end

    it "raises an exception when the installation URL is empty" do
      expect(Yast::InstURL).to receive(:installInf2Url).and_return("")
      expect { described_class.public_send(method) }.to(
        raise_exception(/The installation URL is not set/)
      )
    end
  end

  describe "#contain_multi_repos?" do
    include_examples(:check_inst_url, :contain_multi_repos?)

    it "returns :true if at least two repositories are found on the medium" do
      expect_any_instance_of(Y2Packager::RepomdDownloader)
        .to receive(:product_repos).and_return(
          [
            ["Basesystem-Module 15.1-0", "/Module-Basesystem"],
            ["SLES15-SP1 15.1-0", "/Product-SLES"]
          ]
        )

      expect(described_class.contain_multi_repos?).to eq(true)
    end

    it "returns false otherwise" do
      expect(described_class.contain_multi_repos?).to eq(false)
    end
  end

  describe "contain_repo?" do
    include_examples(:check_inst_url, :contain_repo?)

    it "returns true if there are multiple repositories" do
      expect_any_instance_of(Y2Packager::RepomdDownloader)
        .to receive(:product_repos).and_return(
          [
            ["Basesystem-Module 15.1-0", "/Module-Basesystem"],
            ["SLES15-SP1 15.1-0", "/Product-SLES"]
          ]
        )

      expect(described_class.contain_repo?).to eq(true)
    end

    it "returns true if there are single repository" do
      expect_any_instance_of(Y2Packager::RepomdDownloader)
        .to receive(:product_repos).and_return(
          [
            ["SLES15-SP1 15.1-0", "/"]
          ]
        )

      prod = Y2Packager::RepoProductSpec.new(name: "SLES", dir: "/", base: true)
      allow(products_reader).to receive(:products).and_return([prod])

      expect(described_class.contain_repo?).to eq(true)
    end

    it "returns false there are no repository" do
      expect(described_class.contain_repo?).to eq(false)
    end
  end
end
