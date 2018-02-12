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
require "y2packager/dialogs/product_license_translations"
require "y2packager/product"

describe Y2Packager::Dialogs::ProductLicenseTranslations do
  subject(:dialog) { described_class.new(product, language) }
  let(:product) { instance_double("Y2Packager::Product") }
  let(:language) { "en_US" }

  describe "#contents" do
    it "includes a ProductLicenseTranslations widget" do
      expect(Y2Packager::Widgets::ProductLicenseTranslations).to receive(:new)
        .with(product, language).and_call_original
      expect(dialog.contents.to_s).to include("Widgets::ProductLicenseTranslations")
    end
  end

  describe "#language" do
    context "when it is not specified" do
      before do
        allow(Yast::Language).to receive(:language).and_return("de_DE")
      end

      it "uses the system's current language" do
        dialog = described_class.new(product)
        expect(dialog.language).to eq("de_DE")
      end
    end

    context "when it is specified" do
      it "uses the given one" do
        dialog = described_class.new(product, "cs_CZ")
        expect(dialog.language).to eq("cs_CZ")
      end
    end
  end
end
