# Copyright (c) [2021] SUSE LLC
#
# All Rights Reserved.
#
# This program is free softwayou can redistribute it and/or modify it
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
require "y2packager/libzypp_product_spec"
require "y2packager/product"

describe Y2Packager::LibzyppProductSpec do
  subject(:product_spec) do
    described_class.new(
      name: "sles", display_name: "SLES", arch: "x86_64", version: "15.3"
    )
  end

  describe "#select" do
    let(:product) { instance_double(Y2Packager::Product, select: nil) }

    before do
      allow(product_spec).to receive(:to_product).and_return(product)
    end

    it "selects the underlying libzypp product" do
      expect(product).to receive(:select)
      product_spec.select
    end
  end
end
