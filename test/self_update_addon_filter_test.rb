#!/usr/bin/env rspec

require_relative "test_helper"
require "y2packager/self_update_addon_filter"

describe Y2Packager::SelfUpdateAddonFilter do
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
    let(:roles_packages) do
      [
        ["system-role-server-default", :CAND, :NONE]
      ]
    end

    let(:pkg_src) { 42 }

    before do
      expect(Yast::Pkg).to receive(:PkgQueryProvides).with("system-installation()")
        .and_return(packages)
      expect(Yast::Pkg).to receive(:PkgQueryProvides).with("product()")
        .and_return(product_packages)
      expect(Yast::Pkg).to receive(:PkgQueryProvides).with("installer_module_extension()")
        .and_return(roles_packages)
    end

    it "returns packages providing 'system-installation()' from the required repository" do
      expect(Y2Packager::Resolvable).to receive(:any?)
        .with(kind: :package, name: //, source: pkg_src)
        .and_return(true).exactly(4).times

      expect(Y2Packager::SelfUpdateAddonFilter.packages(pkg_src)).to contain_exactly(
        "skelcd-control-SLED", "skelcd-control-SLES", "SLES-release", "system-role-server-default"
      )
    end

    it "returns an empty list if the packages are not from the required repository" do
      expect(Y2Packager::Resolvable).to receive(:any?)
        .with(kind: :package, name: //, source: pkg_src)
        .and_return(false).exactly(4).times

      expect(Y2Packager::SelfUpdateAddonFilter.packages(pkg_src)).to eq([])
    end
  end
end
