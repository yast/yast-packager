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
require "y2packager/widgets/product_license_content"
require "y2packager/product"

describe Y2Packager::Widgets::ProductLicenseContent do
  include_examples "CWM::CustomWidget"

  subject(:widget) { described_class.new(product, language) }

  let(:language) { "de_DE" }
  let(:product) { instance_double(Y2Packager::Product, license: "content") }

  describe "#contents" do
    it "includes license content in the given language" do
      expect(product).to receive(:license).with(language)
        .and_return("license content")
      widget.contents
    end
  end

  describe "#translate" do
    let(:richtext) { CWM::RichText.new }

    before do
      allow(product).to receive(:license).with("es_ES")
        .and_return("content es_ES")
      allow(CWM::RichText).to receive(:new).and_return(richtext)
    end

    it "shows license content in the given language" do
      widget.contents
      expect(richtext).to receive(:value=).with(/content es_ES/)
      widget.translate("es_ES")
    end
  end
end
