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
require "y2packager/repo_product_spec"
require "y2packager/product"

describe Y2Packager::RepoProductSpec do
  subject(:product_spec) do
    described_class.new(
      name: "sles", display_name: "SLES", arch: "x86_64", version: "15.3",
      order: 1, base: true, depends_on: [], dir: "/SLES-15.3", media_name: "",
      description: "SLES Description"
    )
  end

  describe ".new" do
    before do
      allow(Yast::Arch).to receive(:architecture).and_return("x86_64")
    end

    context "when only name and dir are specified" do
      it "sets default values" do
        product_spec = described_class.new(name: "SLES", dir: "/SLES")
        expect(product_spec.name).to eq("SLES")
        expect(product_spec.dir).to eq("/SLES")
        expect(product_spec.media_name).to eq("/SLES")
        expect(product_spec.arch).to eq("x86_64")
        expect(product_spec.version).to be_nil
        expect(product_spec.order).to be_nil
      end
    end
  end

  describe "#select" do
    let(:product) { instance_double(Y2Packager::Product, select: nil) }
    let(:url) { "http://example.com" }

    before do
      allow(product_spec).to receive(:to_product).and_return(product)
      allow(product).to receive(:selected?).and_return(true)
      allow(Yast::InstURL).to receive(:installInf2Url).and_return(url)
      allow(Yast::Packages).to receive(:Initialize_StageInitial)
      allow(Yast::Pkg).to receive(:ResolvableInstall)
      allow(Yast::AddOnProduct).to receive(:SetBaseProductURL)
      allow(Yast::WorkflowManager).to receive(:SetBaseWorkflow)
    end

    it "adds the repository and selects the product" do
      expect(Yast::Packages).to receive(:Initialize_StageInitial)
        .with(true, url, url, product_spec.dir)
      expect(product).to receive(:select)
      product_spec.select
    end
  end
end
