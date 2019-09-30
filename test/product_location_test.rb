#! /usr/bin/env rspec

require_relative "./test_helper"
require "uri"

require "y2packager/product_location"

# a helper method, find a specified product in the list
def find_product(arr, product)
  arr.find { |p| p.details.product == product }
end

# URL of the local testing repository
REPO_URL = "dir://#{URI.escape(File.join(DATA_PATH, "zypp/test_offline_repo"))}".freeze

describe Y2Packager::ProductLocation do
  let(:scan_result) { Y2Packager::ProductLocation.scan(REPO_URL) }

  before do
    # the testing repository only contains the x86_64 packages/products
    # and the solver ignores the packages for incompatible architectures,
    # that means the test would fail anywhere except on x86_64.
    #
    # So we modify the "setarch" call to always pass the "x86_64" parameter.
    allow_any_instance_of(::Solv::Pool).to receive(:setarch)
      .and_wrap_original do |method, *_args|
        method.call("x86_64")
      end
  end

  describe ".scan" do
    it "finds all product repositories" do
      # there are 3 testing product repositories
      expect(scan_result.size).to eq(3)
      # match_array ignores the order of the items
      expect(scan_result.map { |p| p.details.product }).to match_array(
        ["SLES", "sle-module-basesystem", "sle-module-server-applications"]
      )
    end

    it "reads the product descriptions" do
      base_module = find_product(scan_result, "sle-module-basesystem")
      expect(base_module.details.description).to include("SUSE Linux Enterprise Basesystem Module")
    end

    it "finds the base products" do
      base_products = scan_result.select { |p| p.details.base }
      # there is only the SLES base product in the testing repository
      expect(base_products.map { |p| p.details.product }).to eq(["SLES"])
    end

    it "finds the modules/extensions" do
      modules = scan_result.reject { |p| p.details.base }
      # there are 2 modules in the testing repository
      expect(modules.map { |p| p.details.product }).to match_array(
        ["sle-module-basesystem", "sle-module-server-applications"]
      )
    end

    it "finds the dependencies" do
      sles = find_product(scan_result, "SLES")
      base_module = find_product(scan_result, "sle-module-basesystem")
      server_module = find_product(scan_result, "sle-module-server-applications")

      expect(sles.details.depends_on).to eq([])
      expect(base_module.details.depends_on).to eq(["/Product-SLES"])
      expect(server_module.details.depends_on).to match_array(
        ["/Module-Basesystem", "/Product-SLES"]
      )
    end

    it "return empty list when there is only one repository" do
      expect(Yast::Pkg).to receive(:RepositoryScan).and_return([["/", "Foo product"]])
      expect(described_class.scan(REPO_URL)).to eq([])
    end

    it "return empty list when there is none repository found" do
      expect(Yast::Pkg).to receive(:RepositoryScan).and_return([])
      expect(described_class.scan(REPO_URL)).to eq([])
    end
  end

  describe "#summary" do
    subject { described_class.new("foo", "/dir/foo", product: product) }

    context "when there is no details" do
      let(:product) { nil }

      it "returns nil" do
        expect(subject.summary).to be_nil
      end
    end

    context "when there is details" do
      let(:product) { instance_double(Y2Packager::ProductLocationDetails, summary: summary) }

      context "and the summary is nil" do
        let(:summary) { nil }

        it "returns nil" do
          expect(subject.summary).to be_nil
        end
      end

      context "and the summary is empty" do
        let(:summary) { "" }

        it "returns nil" do
          expect(subject.summary).to be_nil
        end
      end

      context "and the summary has content" do
        let(:summary) { "a summary" }

        it "returns the summary content" do
          expect(subject.summary).to eq(summary)
        end
      end
    end
  end

  describe "#label" do
    subject { described_class.new("foo", "/dir/foo", product: product) }
    let(:product) { instance_double(Y2Packager::ProductLocationDetails, summary: "summary") }

    it "returns the summary content" do
      expect(subject.label).to eq("summary")
    end
  end

  describe "#selected?" do
    subject { described_class.new("foo", "/dir/foo", product: product) }
    let(:product) { instance_double(Y2Packager::ProductLocationDetails, product: "product") }

    before do
      expect(Y2Packager::Resolvable).to receive(:any?)
        .with(kind: :product, name: "product", status: :selected)
        .and_return(product_selected)
    end

    context "product selected" do
      let(:product_selected) { true }
      it "returns true" do
        expect(subject.selected?).to eq(true)
      end
    end

    context "product not selected" do
      let(:product_selected) { false }
      it "returns false" do
        expect(subject.selected?).to eq(false)
      end
    end
  end
end
