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

    it "returns biosdevname within the list of packages as required by Kernel params" do
      Yast::SCR.stub(:Read).with(
        Yast::Path.new(".target.string"),
        "/proc/cmdline"
      ).and_return("install=cd:// vga=0x314 biosdevname=1")
      expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to be_true
    end

    it "does not return biosdevname within the list of packages as not required by Kernel params" do
      Yast::SCR.stub(:Read).with(
        Yast::Path.new(".target.string"),
        "/proc/cmdline"
      ).and_return("install=cd:// vga=0x314 biosdevname=0")
      expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to be_false
    end

    it "returns biosdevname within the list of packages if biosdevname not specified as Kernel parameter and if running on a Dell system" do
      Yast::SCR.stub(:Read).with(
        Yast::Path.new(".target.string"),
        "/proc/cmdline"
      ).and_return("install=cd:// vga=0x314")
      # 0 means `grep` succeeded
      Yast::SCR.stub(:Execute).and_return(0)
      expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to be_true
    end

    it "does not return biosdevname within the list of packages if biosdevname not specified as Kernel parameter and if not running on a Dell system" do
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
