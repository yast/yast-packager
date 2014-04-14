#! /usr/bin/env rspec

ENV["Y2DIR"] = File.expand_path("../../src", __FILE__)

require "yast"

Yast.import "Packages"
Yast.import "SCR"
Yast.import "Product"

describe Yast::Packages do
  describe "#kernelCmdLinePackages" do
    before(:each) do
      # default value
      Yast::SCR.stub(:Read).and_return(nil)
      Yast::Product.stub(:Product).and_return(nil)
    end

    context "when biosdevname behavior explicitly defined on the Kenel command line" do
      it "returns biosdevname within the list of required packages" do
        Yast::SCR.stub(:Read).with(
          Yast::Path.new(".target.string"),
          "/proc/cmdline"
        ).and_return("install=cd:// vga=0x314 biosdevname=1")
        expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to be_true
      end

      it "does not return biosdevname within the list of required packages" do
        Yast::SCR.stub(:Read).with(
          Yast::Path.new(".target.string"),
          "/proc/cmdline"
        ).and_return("install=cd:// vga=0x314 biosdevname=0")
        expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to be_false
      end
    end

    context "when biosdevname behavior not defined on the Kernel command line" do
      context "and running on a Dell system" do
        it "returns biosdevname within the list of packages" do
          Yast::SCR.stub(:Read).with(
            Yast::Path.new(".target.string"),
            "/proc/cmdline"
          ).and_return("install=cd:// vga=0x314")
          # 0 means `grep` succeeded
          Yast::SCR.stub(:Execute).and_return(0)
          expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to be_true
        end
      end

      context "and running on a non-Dell system" do
        it "does not return biosdevname within the list of packages" do
          Yast::SCR.stub(:Read).with(
            Yast::Path.new(".target.string"),
            "/proc/cmdline"
          ).and_return("install=cd:// vga=0x314")
          # 1 means `grep` has not succeeded
          Yast::SCR.stub(:Execute).and_return(1)
          expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to be_false
        end
      end
    end

  end
end
