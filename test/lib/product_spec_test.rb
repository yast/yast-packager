# Copyright (c) [2021] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require_relative "../test_helper"
require "y2packager/product_spec"

describe Y2Packager::ProductSpec do
  describe ".base_products" do
    let(:reader) { Y2Packager::ProductSpecReader.new }

    let(:base) do
      Y2Packager::ProductSpec.new(
        name: "SLES", display_name: "SUSE Linux Enterprise Server", order: 1, version: "15.3",
        arch: :x86_64, base: true
      )
    end

    let(:addon) do
      Y2Packager::ProductSpec.new(
        name: "sles-basesystem-module", display_name: "Basesystem Module", order: 2, version: "15.3",
        arch: :x86_64, base: false
      )
    end

    before do
      allow(Y2Packager::ProductSpecReader).to receive(:new).and_return(reader)
      allow(reader).to receive(:products).and_return([base, addon])
    end

    it "returns the base products" do
      products = described_class.base_products
      expect(products.map(&:name)).to eq(["SLES"])
    end
  end
end
