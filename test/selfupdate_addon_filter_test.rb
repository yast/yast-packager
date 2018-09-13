#!/usr/bin/env rspec

require_relative "test_helper"
require "y2packager/selfupdate_addon_filter"

describe Y2Packager::SelfupdateAddonFilter do
  describe ".packages" do
    let(:packages) do
      [
        ["skelcd-control-SLED", :CAND, :NONE],
        ["skelcd-control-SLES", :CAND, :NONE]
      ]
    end
    let(:product_packages) do
      [
        ["SLES-release", :CAND, :NONE]
      ]
    end
    let(:pkg_src) { 42 }

    before do
      expect(Yast::Pkg).to receive(:PkgQueryProvides).with("system-installation()")
        .and_return(packages)
      expect(Yast::Pkg).to receive(:PkgQueryProvides).with("product()")
        .and_return(product_packages)
    end

    it "returns packages providing 'system-installation()' from the required repository" do
      expect(Yast::Pkg).to receive(:ResolvableProperties).with(anything, :package, "")
        .and_return(["source" => pkg_src]).exactly(3).times

      expect(Y2Packager::SelfupdateAddonFilter.packages(pkg_src)).to eq(
        ["skelcd-control-SLED", "skelcd-control-SLES", "SLES-release"]
      )
    end

    it "returns an empty list if the packages are not from the required repository" do
      expect(Yast::Pkg).to receive(:ResolvableProperties).with(anything, :package, "")
        .and_return(["source" => 999]).exactly(3).times

      expect(Y2Packager::SelfupdateAddonFilter.packages(pkg_src)).to eq([])
    end
  end
end
