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

require_relative "../../test_helper"
require "y2packager/product_spec_readers/libzypp"
require "y2packager/product"

describe Y2Packager::ProductSpecReaders::Libzypp do
  subject(:reader) { described_class.new }

  describe "#products" do
    let(:sles) do
      Y2Packager::Product.new(
        name: "SLES", display_name: "SUSE Linux Enterprise Server", order: 1, version: "15.3",
        arch: :x86_64
      )
    end

    let(:sled) do
      Y2Packager::Product.new(
        name: "SLED", display_name: "SUSE Linux Enterprise Desktop", order: 2, version: "15.3",
        arch: :x86_64
      )
    end

    before do
      allow(Y2Packager::Product).to receive(:available_base_products).and_return([sles, sled])
    end

    it "returns an spec for each product" do
      specs = reader.products
      sles_spec, sled_spec = specs
      expect(sles_spec.name).to eq(sles.name)
      expect(sles_spec.display_name).to eq(sles.display_name)
      expect(sled_spec.name).to eq(sled.name)
      expect(sled_spec.display_name).to eq(sled.display_name)
    end
  end
end
