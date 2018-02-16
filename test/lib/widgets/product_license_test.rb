#!/usr/bin/env rspec

require_relative "../../test_helper"
require "cwm/abstract_widget"
require "cwm/rspec"
require "y2packager/widgets/product_license"
require "y2packager/product"

describe Y2Packager::Widgets::ProductLicense do
  include_examples "CWM::CustomWidget"

  before do
    allow(Yast::Language).to receive(:language).and_return(language)
  end

  subject(:widget) { described_class.new(product) }

  let(:language) { "de_DE" }
  let(:license_confirmation_required?) { true }
  let(:product) do
    instance_double(
      Y2Packager::Product,
      license:                        "license_content",
      license_confirmation_required?: license_confirmation_required?
    )
  end

  describe "#contents" do
    let(:confirmation_widget) { Yast::Term.new(:confirmation_widget) }

    before do
      allow(Y2Packager::Widgets::ProductLicenseConfirmation).to receive(:new)
        .and_return(confirmation_widget)
    end

    it "shows the license in the given language" do
      expect(Y2Packager::Widgets::ProductLicenseContent).to receive(:new)
        .with(product, language).and_return("de_DE license")
      expect(widget.contents.to_s).to include("de_DE license")
    end

    it "includes a confirmation checkbox" do
      expect(Y2Packager::Widgets::ProductLicenseConfirmation).to receive(:new)
        .with(product, skip_validation: false)
      expect(widget.contents.to_s).to include("confirmation_widget")
    end

    context "when validation is disabled" do
      subject(:widget) { described_class.new(product, skip_validation: true) }

      it "disables confirmation widget validation" do
        expect(Y2Packager::Widgets::ProductLicenseConfirmation).to receive(:new)
          .with(product, skip_validation: true)
        expect(widget.contents.to_s).to include("confirmation_widget")
      end
    end

    context "when license confirmation is not needed" do
      let(:license_confirmation_required?) { false }

      it "does includes a confirmation checkbox" do
        expect(widget.contents.to_s).to_not include("confirmation_widget")
      end
    end
  end

  describe "#translate" do
    let(:license_content) { instance_double(Y2Packager::Widgets::ProductLicenseContent) }

    before do
      allow(Y2Packager::Widgets::ProductLicenseContent).to receive(:new)
        .and_return(license_content)
    end

    it "translate the license to the given language" do
      widget.contents
      expect(license_content).to receive(:translate).with("es_ES")
      widget.translate("es_ES")
    end
  end
end
