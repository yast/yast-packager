#!/usr/bin/env rspec
# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE LLC, All Rights Reserved.
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
require "y2packager/widgets/license_translations_button"
require "y2packager/product"

describe Y2Packager::Widgets::LicenseTranslationsButton do
  subject(:widget) { described_class.new(product) }
  let(:product) { instance_double(Y2Packager::Product, license: "content") }

  describe "#handle" do
    let(:dialog) { instance_double(Y2Packager::Dialogs::ProductLicense, run: nil) }

    before do
      allow(Y2Packager::Dialogs::ProductLicense).to receive(:new)
        .with(product).and_return(dialog)
    end

    it "opens a dialog" do
      expect(dialog).to receive(:run)
      widget.handle
    end

    it "returns nil" do
      expect(widget.handle).to be_nil
    end
  end
end
