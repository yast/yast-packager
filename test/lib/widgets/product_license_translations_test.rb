#!/usr/bin/env rspec
# ------------------------------------------------------------------------------
# Copyright (c) 2018 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require_relative "../../test_helper"
require "cwm/rspec"

require "y2packager/widgets/product_license_translations"
require "y2packager/product"

RSpec::Matchers.define :array_not_including do |x|
  match do |actual|
    return false unless actual.is_a?(Array)
    !actual.include?(x)
  end
end

describe Y2Packager::Widgets::ProductLicenseTranslations do
  include_examples "CWM::CustomWidget"

  subject(:widget) { described_class.new(product, language) }

  let(:language) { "de_DE" }
  let(:product) do
    instance_double(
      Y2Packager::Product,
      license_locales: ["en_US", "de_DE", "ja_JP"],
      license:         "content"
    )
  end

  before do
    allow(Yast::Language).to receive(:supported_language?).and_return(true)
  end

  describe "#contents" do
    it "includes a language selector" do
      expect(Y2Packager::Widgets::SimpleLanguageSelection).to receive(:new)
      widget.contents
    end

    it "includes the product license text" do
      expect(Y2Packager::Widgets::ProductLicenseContent).to receive(:new)
      widget.contents
    end

    context "when selected language cannot be displayed" do
      before do
        allow(Yast::Language).to receive(:supported_language?)
          .with(language).and_return(false)
      end

      it "does not include it in the language selector" do
        expect(Y2Packager::Widgets::SimpleLanguageSelection).to receive(:new)
          .with(array_not_including("de_DE"), anything)
        widget.contents
      end

      it "shows the product license in the default language (AmE)" do
        expect(Y2Packager::Widgets::ProductLicenseContent).to receive(:new)
          .with(product, "en_US")
        widget.contents
      end
    end

    context "when there is no translation for the given language" do
      let(:language) { "hu_HU" }

      it "does not include it in the language selector" do
        expect(Y2Packager::Widgets::SimpleLanguageSelection).to receive(:new)
          .with(array_not_including("hu_HU"), anything)
        widget.contents
      end

      it "shows the product license in the default language (AmE)" do
        expect(Y2Packager::Widgets::ProductLicenseContent).to receive(:new)
          .with(product, "en_US")
        widget.contents
      end
    end
  end

  describe "#handle" do
    let(:language_widget) do
      Y2Packager::Widgets::SimpleLanguageSelection.new(["en_US", "es"], "en_US")
    end
    let(:content_widget) { instance_double(Y2Packager::Widgets::ProductLicenseContent) }

    before do
      allow(Y2Packager::Widgets::SimpleLanguageSelection).to receive(:new)
        .and_return(language_widget)
      allow(Y2Packager::Widgets::ProductLicenseContent).to receive(:new)
        .and_return(content_widget)
    end

    context "when the event comes from the language selector" do
      let(:event) { { "ID" => language_widget.widget_id } }

      before do
        allow(language_widget).to receive(:value).and_return("es")
      end

      it "translates the license content" do
        expect(content_widget).to receive(:translate).with("es")
        widget.handle(event)
      end
    end

    context "when the event comes from another widget" do
      let(:event) { { "ID" => "other_widget" } }

      it "does not translate the license content" do
        expect(content_widget).to_not receive(:translate)
        widget.handle(event)
      end
    end
  end
end
