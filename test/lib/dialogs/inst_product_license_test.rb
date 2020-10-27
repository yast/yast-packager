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
require "y2packager/dialogs/inst_product_license"
require "y2packager/product"

describe Y2Packager::Dialogs::InstProductLicense do
  subject(:dialog) { described_class.new(product) }
  let(:product) do
    instance_double(Y2Packager::Product)
  end

  let(:language) { "en_US" }
  let(:confirmation_required) { true }

  describe "#contents" do
    before do
      allow(Yast::Language).to receive(:language).and_return(language)
      allow(product).to receive(:license_confirmation_required?).and_return(confirmation_required)
    end

    context "when license acceptance is required" do
      it "includes a confirmation checkbox" do
        expect(Y2Packager::Widgets::ProductLicenseConfirmation).to receive(:new).with(product)

        dialog.contents
      end
    end

    context "when license acceptance is not required" do
      let(:confirmation_required) { false }

      it "doest not include a confirmation checkbox" do
        expect(Y2Packager::Widgets::ProductLicenseConfirmation).to_not receive(:new).with(product)

        dialog.contents
      end
    end

    it "includes product translations using the current language as default" do
      expect(Y2Packager::Widgets::ProductLicenseTranslations).to receive(:new)
        .with(product, language)
      dialog.contents
    end
  end

  describe "#abort_handler" do
    it "returns true if user confirm abort" do
      allow(Yast::Popup).to receive(:ConfirmAbort).and_return(true)

      expect(subject.abort_handler).to eq true
    end

    it "returns false if user cancel abort confirmation" do
      allow(Yast::Popup).to receive(:ConfirmAbort).and_return(false)

      expect(subject.abort_handler).to eq false
    end
  end
end
