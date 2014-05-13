#! /usr/bin/env rspec

ENV["Y2DIR"] = File.expand_path("../../src", __FILE__)

require "yast"
require "yaml"

include Yast::Logger

Yast.import "Packages"
Yast.import "SCR"
Yast.import "Product"
Yast.import "ProductFeatures"

SCR_STRING_PATH = Yast::Path.new(".target.string")
SCR_BASH_PATH = Yast::Path.new(".target.bash")

CHECK_FOR_DELL_SYSTEM = Regexp.new(
  'hwinfo .*bios .*grep .*vendor:.*dell inc',
  Regexp::IGNORECASE
)

# Path to a test data - service file - mocking the default data path
DATA_PATH = File.join(File.expand_path(File.dirname(__FILE__)), "data")

def load_zypp(file_name)
  file_name = File.join(DATA_PATH, "zypp", file_name)
  log.info "Loading file: #{file_name}"
  YAML.load_file(file_name)
end

PRODUCTS_FROM_ZYPP = load_zypp('products.yml').freeze

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
          SCR_STRING_PATH,"/proc/cmdline"
        ).and_return("install=cd:// vga=0x314 biosdevname=1")
        expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to be_true
      end

      it "does not return biosdevname within the list of required packages" do
        Yast::SCR.stub(:Read).with(
          SCR_STRING_PATH,"/proc/cmdline"
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
          Yast::SCR.stub(:Execute).with(SCR_BASH_PATH, CHECK_FOR_DELL_SYSTEM).and_return(0)
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
          Yast::SCR.stub(:Execute).with(SCR_BASH_PATH, CHECK_FOR_DELL_SYSTEM).and_return(1)
          expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to be_false
        end
      end
    end

  end

  describe "#default_patterns" do
    context "software->default_patterns is not defined in control file" do
      it "returns empty list" do
        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "default_patterns").and_return("")
        expect(Yast::Packages.default_patterns).to be_empty
      end
    end

    context "software->default_patterns is filled with list of patterns" do
      it "returns list of patterns" do
        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "default_patterns").and_return("a,b,c,d")
        expect(Yast::Packages.default_patterns).to eq(["a", "b", "c", "d"])

        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "default_patterns").and_return("a b c d")
        expect(Yast::Packages.default_patterns).to eq(["a", "b", "c", "d"])

        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "default_patterns").and_return("  a ,b , c,d  ")
        expect(Yast::Packages.default_patterns).to eq(["a", "b", "c", "d"])

        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "default_patterns").and_return("  a ,b \n, c\n,d  ")
        expect(Yast::Packages.default_patterns).to eq(["a", "b", "c", "d"])
      end
    end
  end

  DEFAULT_PATTERN = {
    "name" => "name",
    "version" => "1.0.0",
    "status" => :available,
    "transact_by" => :app_high,
  }

  def pattern(properties = {})
    DEFAULT_PATTERN.merge(properties)
  end

  describe "#SelectSystemPatterns" do
    context "if this is the initial run or it is being reinitialized" do
      context "and patterns are not unselected by user" do
        it "selects patterns for installation" do
          Yast::Packages.stub(:patterns_to_install).and_return(["p1", "p2", "p3"])
          Yast::Pkg.stub(:ResolvableProperties).and_return(
            [pattern({ "name" => "p1" })],
            [pattern({ "name" => "p2" })],
            [pattern({ "name" => "p3" })]
          )

          allow(Yast::Pkg).to receive(:ResolvableInstall).with(/\Ap[1-3]/, :pattern).exactly(3).times.and_return(true)
          Yast::Packages.SelectSystemPatterns(false)
        end
      end

      context "and some patterns are already unselected by user" do
        it "selects patterns for installation that were not unselected by user already" do
          Yast::Packages.stub(:patterns_to_install).and_return(["p1", "p2", "p3"])
          Yast::Pkg.stub(:ResolvableProperties).and_return(
            [pattern({ "name" => "p1", "transact_by" => :user })],
            [pattern({ "name" => "p2", "transact_by" => :user })],
            [pattern({ "name" => "p3" })]
          )

          expect(Yast::Pkg).not_to receive(:ResolvableInstall).with("p1", :pattern)
          expect(Yast::Pkg).not_to receive(:ResolvableInstall).with("p2", :pattern)
          expect(Yast::Pkg).to receive(:ResolvableInstall).with("p3", :pattern).once.and_return(true)
          Yast::Packages.SelectSystemPatterns(false)
        end
      end
    end

    context "if this is a subsequent run" do
      it "re-selects all patterns already selected for installation" do
        Yast::Packages.stub(:patterns_to_install).and_return(["p1", "p2", "p3"])
        Yast::Pkg.stub(:ResolvableProperties).and_return(
          [pattern({ "name" => "p1", "transact_by" => :user, "status" => :selected })],
          [pattern({ "name" => "p2", "transact_by" => :user, "status" => :selected })],
          [pattern({ "name" => "p3" })]
        )

        expect(Yast::Pkg).to receive(:ResolvableRemove).with(/\Ap[1-2]/, :pattern).twice.and_return(true)
        expect(Yast::Pkg).not_to receive(:ResolvableInstall).with("p3", :pattern)
        Yast::Packages.SelectSystemPatterns(true)
      end
    end

    it "reports an error if pattern is not found" do
      default_patterns = ["p1", "p2", "p3"]

      Yast::Packages.stub(:patterns_to_install).and_return(default_patterns)
      Yast::Pkg.stub(:ResolvableProperties).and_return([])
      Yast::Report.stub(:Error).and_return(nil)

      # Called twice with reselect=true/false
      Yast::Packages.SelectSystemPatterns(true)
      Yast::Packages.SelectSystemPatterns(false)

      expect(Yast::Report).to have_received(:Error).with(/pattern p[1-3]/i).exactly(2 * default_patterns.size).times
    end
  end

  describe "#log_software_selection" do
    it "logs all currently changed resolvables set by user or application (excluding solver)" do
      Yast::Pkg.stub(:ResolvableProperties).and_return([])
      Yast::Pkg.stub(:ResolvableProperties).with("", :product, "").and_return(PRODUCTS_FROM_ZYPP.dup)

      expect(Yast::Y2Logger.instance).to receive(:info) do |msg|
        expect(msg).to match(/(transaction status [begin|end]|(locked)?resolvables of type .* set by .*|:name=>.*:version=>)/i)
      end.exactly(8).times.and_call_original

      expect(Yast::Packages.log_software_selection).to be_nil
    end
  end
end
