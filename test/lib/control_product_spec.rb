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
require "y2packager/control_product_spec"
require "y2packager/product"

describe Y2Packager::ControlProductSpec do
  subject(:product_spec) do
    described_class.new(
      name: "sles", display_name: "SLES", arch: "x86_64", version: "15.3",
      order: 1, license_url: "http://example.com", register_target: "sles"
    )
  end

  describe "#select" do
    it "selects the product" do
      expect { product_spec.select }.to change { product_spec.selected? }.from(false).to(true)
    end
  end
end
