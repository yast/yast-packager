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
    described_class.instance_variable_set(:@detected_type, nil)
  end

  describe "#type" do
    let(:reader) { instance_double(Y2Packager::ProductSpecReaders::Full) }

    before do
      allow(Y2Packager::ProductSpecReaders::Full).to receive(:new).and_return(reader)
    end

    it "raises an exception when the installation URL is nil" do
      expect(Yast::InstURL).to receive(:installInf2Url).and_return(nil)
      expect { described_class.type }.to raise_exception(/The installation URL is not set/)
    end

    it "raises an exception when the installation URL is empty" do
      expect(Yast::InstURL).to receive(:installInf2Url).and_return("")
      expect { described_class.type }.to raise_exception(/The installation URL is not set/)
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

    context "missing media.1/products on the installation medium" do
      before do
        expect_any_instance_of(Y2Packager::RepomdDownloader)
          .to receive(:product_repos).and_return([])
      end

      it "returns :online if the repository does not contain any base product" do
        expect(reader).to receive(:products).and_return([])
        expect(described_class.type).to eq(:online)
      end
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
        expect(reader).to receive(:products).and_return([])
        expect(described_class.type).to eq(:online)
      end

      it "returns :standard if the repository contains any base product" do
        prod = Y2Packager::RepoProductSpec.new(
          name: "sles", dir: "/SLES", base: true
        )

        expect(reader).to receive(:products).and_return([prod])
        expect(described_class.type).to eq(:standard)
      end
    end
  end

  describe "type=" do
    it "sets type to given argument" do
      described_class.type = :online
      expect(described_class.type).to eq :online
    end

    it "raises ArgumentError for invalid value" do
      expect { described_class.type = :invalid }.to raise_error(ArgumentError)
    end
  end

  def mock_arguments(arg)
    allow(Yast::WFM).to receive(:Args).and_return([arg])
    allow(Yast::WFM).to receive(:Args).with(0).and_return(arg)
  end

  describe "#skip_step?" do
    context "online installation medium" do
      before do
        allow(Y2Packager::MediumType).to receive(:type).and_return(:online)
      end

      it "returns true if the client args contain \"skip\" => \"online\"" do
        mock_arguments("skip" => "online")
        expect(Y2Packager::MediumType.skip_step?).to eq(true)
      end
      it "returns true if the client args contain \"skip\" => \"standard,online\"" do
        mock_arguments("skip" => "standard,online")
        expect(Y2Packager::MediumType.skip_step?).to eq(true)
      end
      it "returns false if the client args do not contain \"skip\" => \"online\"" do
        mock_arguments({})
        expect(Y2Packager::MediumType.skip_step?).to eq(false)
      end
      it "returns false if the client args contain \"only\" => \"online\"" do
        mock_arguments("only" => "online")
        expect(Y2Packager::MediumType.skip_step?).to eq(false)
      end
      it "returns false if the client args contain \"only\" => \"online,standard\"" do
        mock_arguments("only" => "standard,online")
        expect(Y2Packager::MediumType.skip_step?).to eq(false)
      end
      it "returns false if the client args do not contain \"only\" => \"online\"" do
        mock_arguments({})
        expect(Y2Packager::MediumType.skip_step?).to eq(false)
      end
      it "returns false if the client args are empty" do
        allow(Yast::WFM).to receive(:Args).and_return([])
        expect(Y2Packager::MediumType.skip_step?).to eq(false)
      end
    end
  end
end
