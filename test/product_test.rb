#!/usr/bin/env rspec

require_relative "test_helper"

require "y2packager/product"

describe Y2Packager::Product do
  BASE_ATTRS = {
    name: "openSUSE", version: "20160405", arch: "x86_64",
    category: "addon", status: :installed, vendor: "openSUSE"
  }.freeze

  subject(:product) do
    Y2Packager::Product.new(BASE_ATTRS)
  end

  describe "==" do
    context "when name, arch, version and vendor match" do
      let(:other) { Y2Packager::Product.new(BASE_ATTRS) }

      it "returns true" do
        expect(subject == other).to eq(true)
      end
    end

    context "when name does not match" do
      let(:other) { Y2Packager::Product.new(BASE_ATTRS.merge(name: "other")) }

      it "returns false" do
        expect(subject == other).to eq(false)
      end
    end

    context "when version does not match" do
      let(:other) { Y2Packager::Product.new(BASE_ATTRS.merge(version: "20160409")) }

      it "returns false" do
        expect(subject == other).to eq(false)
      end
    end

    context "when arch does not match" do
      let(:other) { Y2Packager::Product.new(BASE_ATTRS.merge(arch: "i586")) }

      it "returns false" do
        expect(subject == other).to eq(false)
      end
    end

    context "when vendor does not match" do
      let(:other) { Y2Packager::Product.new(BASE_ATTRS.merge(vendor: "SUSE")) }

      it "returns false" do
        expect(subject == other).to eq(false)
      end
    end
  end

  describe "#selected?" do
    before do
      allow(Yast::Pkg).to receive(:ResolvableProperties).with(product.name, :product, "")
        .and_return([{ "name" => product.name, "status" => status }])
    end

    context "if product was selected for installation" do
      let(:status) { :selected }

      it "returns true" do
        expect(product).to be_selected
      end
    end

    context "if product was not selected for installation" do
      let(:status) { :none }

      it "returns false" do
        expect(product).to_not be_selected
      end
    end
  end

  describe "#select" do
    it "selects the product for installation" do
      expect(Yast::Pkg).to receive(:ResolvableInstall).with(product.name, :product, "")
      product.select
    end
  end

  describe "#restore" do
    it "restores product status" do
      expect(Yast::Pkg).to receive(:ResolvableNeutral).with(product.name, :product, true)
      product.restore
    end
  end

  describe "#label" do
    context "when 'display_name' is present" do
      subject(:product) do
        Y2Packager::Product.new(name: "NAME", display_name: "DISPLAY", short_name: "SHORT")
      end

      it "returns 'display_name'" do
        expect(product.label).to eq("DISPLAY")
      end
    end

    context "when 'display_name' is not present" do
      subject(:product) { Y2Packager::Product.new(name: "NAME", short_name: "SHORT") }

      it "returns 'short_name'" do
        expect(product.label).to eq("SHORT")
      end
    end

    context "when 'display_name' nor 'short_name' are present" do
      subject(:product) { Y2Packager::Product.new(name: "NAME") }

      it "returns 'name'" do
        expect(product.label).to eq("NAME")
      end
    end
  end

  describe "#license_to_confirm" do
    let(:license) { "license content" }
    let(:lang) { "en_US" }

    before do
      allow(Yast::Pkg).to receive(:PrdGetLicenseToConfirm).with(product.name, lang)
        .and_return(license)
    end

    it "return the license" do
      expect(product.license_to_confirm(lang)).to eq(license)
    end

    context "when the no license to confirm was found" do
      let(:license) { "" }

      it "return the empty string" do
        expect(product.license_to_confirm(lang)).to eq("")
      end
    end

    context "when the product does not exist" do
      let(:license) { nil }

      it "return nil" do
        expect(product.license_to_confirm(lang)).to be_nil
      end
    end

    context "when a language was not specified" do
      let(:current_language) { "de_DE" }

      before do
        allow(Yast::Language).to receive(:language).and_return(current_language)
      end

      it "uses the YaST current language" do
        expect(Yast::Pkg).to receive(:PrdGetLicenseToConfirm).with(product.name, current_language)
        product.license_to_confirm
      end
    end
  end

  describe "#license_confirmation_required?" do
    before do
      allow(Yast::Pkg).to receive(:PrdNeedToAcceptLicense).with(product.name).and_return(needed)
    end

    context "when accepting the license is required" do
      let(:needed) { true }

      it "returns true" do
        expect(product.license_confirmation_required?).to eq(true)
      end
    end

    context "when accepting the license is not required" do
      let(:needed) { false }

      it "returns false" do
        expect(product.license_confirmation_required?).to eq(false)
      end
    end
  end

  describe "#confirm_license" do
    it "confirms the license" do
      expect(Yast::Pkg).to receive(:PrdMarkLicenseConfirmed).with(product.name)
      product.confirm_license
    end
  end

  describe "#license_confirmed?" do
    before do
      allow(product).to receive(:license_to_confirm).and_return(license)
    end

    context "when a license to be confirmed exists" do
      let(:license) { "license content" }

      it "returns false" do
        expect(product.license_confirmed?).to eq(false)
      end
    end

    context "when there is not license to be confirmed" do
      let(:license) { "" }

      it "returns true" do
        expect(product.license_confirmed?).to eq(true)
      end
    end
  end
end
