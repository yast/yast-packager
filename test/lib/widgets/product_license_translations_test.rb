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

describe Y2Packager::Widgets::ProductLicenseTranslations do
  include_examples "CWM::CustomWidget"

  subject(:widget) { described_class.new(product, language) }

  let(:language) { "de_DE" }
  let(:product) do
    instance_double(Y2Packager::Product, license_locales: ["en_US", "ja"], license: "content")
  end

  describe "#contents" do
    it "includes a language selector" do
      expect(Y2Packager::Widgets::SimpleLanguageSelection).to receive(:new)
        .with(product.license_locales, language)
      widget.contents
    end

    it "includes the product license text" do
      expect(Y2Packager::Widgets::ProductLicenseContent).to receive(:new)
        .with(product, language)
      widget.contents
    end

    context "when running on textmode" do
      let(:preselected) { "ja_JP" }

      before do
        allow(Yast::UI).to receive(:TextMode).and_return(true)
        allow(Yast::Language).to receive(:preselected).and_return(preselected)
        allow(Yast::Stage).to receive(:initial).and_return(initial)
      end

      context "on installation" do
        let(:initial) { true }

        it "the language selector includes only the preselected language" do
          expect(Y2Packager::Widgets::SimpleLanguageSelection).to receive(:new)
            .with([preselected], preselected)
          widget.contents
        end

        it "shows the product license in the preselected language" do
          expect(Y2Packager::Widgets::ProductLicenseContent).to receive(:new)
            .with(product, preselected)
          widget.contents
        end

        context "when there is no translation for the preselected language" do
          let(:preselected) { "hu_HU" }

          it "the language selector includes only 'english'" do
            expect(Y2Packager::Widgets::SimpleLanguageSelection).to receive(:new)
              .with(["en_US"], "en_US")
            widget.contents
          end

          it "shows the product license in 'english'" do
            expect(Y2Packager::Widgets::ProductLicenseContent).to receive(:new)
              .with(product, "en_US")
            widget.contents
          end
        end
      end

      context "on the installed system" do
        let(:initial) { false }
        let(:language) { "ja_JP" }

        it "the language selector includes only the default language" do
          expect(Y2Packager::Widgets::SimpleLanguageSelection).to receive(:new)
            .with([language], language)
          widget.contents
        end

        it "shows the product license in the default language" do
          expect(Y2Packager::Widgets::ProductLicenseContent).to receive(:new)
            .with(product, language)
          widget.contents
        end
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
