#! /usr/bin/env rspec

require_relative "./test_helper"

require "yaml"

include Yast::Logger

Yast.import "Packages"
Yast.import "SCR"
Yast.import "Product"
Yast.import "ProductFeatures"
Yast.import "Linuxrc"
Yast.import "Pkg"

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

def set_root_path(directory)
  root = File.join(DATA_PATH, directory)
  check_version = false
  handle = Yast::WFM.SCROpen("chroot=#{root}:scr", check_version)
  Yast::WFM.SCRSetDefault(handle)
end

PRODUCTS_FROM_ZYPP = load_zypp('products.yml').freeze

describe Yast::Packages do
  before(:each) do
    log.info "--- test ---"
  end

  describe "#kernelCmdLinePackages" do
    before(:each) do
      # default value
      Yast::Product.stub(:Product).and_return(nil)
    end

    after(:each) do
      # set_root_path is always called and it opens a SCR instance
      # that needs to be closed
      Yast::WFM.SCRClose(Yast::WFM.SCRGetDefault)
    end

    context "when biosdevname behavior explicitly defined on the Kenel command line" do
      it "returns biosdevname within the list of required packages" do
        set_root_path("cmdline-biosdevname_1")
        expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to eq(true)
      end

      it "does not return biosdevname within the list of required packages" do
        set_root_path("cmdline-biosdevname_0")
        expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to eq(false)
      end

      it "does not return biosdevname within the list of required packages then value is invalid" do
        set_root_path("cmdline-biosdevname_10")
        expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to eq(false)
      end
    end

    context "when biosdevname behavior not defined on the Kernel command line" do
      before { set_root_path("cmdline-biosdevname_nil") }

      context "and running on a Dell system" do
        it "returns biosdevname within the list of packages" do
          # 0 means `grep` succeeded
          Yast::SCR.stub(:Execute).with(SCR_BASH_PATH, CHECK_FOR_DELL_SYSTEM).and_return(0)
          expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to eq(true)
        end
      end

      context "and running on a non-Dell system" do
        it "does not return biosdevname within the list of packages" do
          # 1 means `grep` has not succeeded
          Yast::SCR.stub(:Execute).with(SCR_BASH_PATH, CHECK_FOR_DELL_SYSTEM).and_return(1)
          expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to eq(false)
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
        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "default_patterns").and_return("a b c d")
        expect(Yast::Packages.default_patterns).to eq(["a", "b", "c", "d"])

        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "default_patterns").and_return("  a    b\t c d\t  ")
        expect(Yast::Packages.default_patterns).to eq(["a", "b", "c", "d"])

        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "default_patterns").and_return("  a b \n c\nd  ")
        expect(Yast::Packages.default_patterns).to eq(["a", "b", "c", "d"])
      end
    end
  end

  describe "#optional_default_patterns" do
    context "software->optional_default_patterns is not defined in control file" do
      it "returns empty list" do
        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "optional_default_patterns").and_return("")
        expect(Yast::Packages.optional_default_patterns).to be_empty
      end
    end

    context "software->optional_default_patterns is filled with list of patterns" do
      it "returns list of patterns" do
        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "optional_default_patterns").and_return("a b c d")
        expect(Yast::Packages.optional_default_patterns).to eq(["a", "b", "c", "d"])

        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "optional_default_patterns").and_return("  a    b\t c d\t  ")
        expect(Yast::Packages.optional_default_patterns).to eq(["a", "b", "c", "d"])

        Yast::ProductFeatures.stub(:GetStringFeature).with("software", "optional_default_patterns").and_return("  a b \n c\nd  ")
        expect(Yast::Packages.optional_default_patterns).to eq(["a", "b", "c", "d"])
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

    it "does not report an error but logs it if optional pattern is not found" do
      optional_default_patterns = ["p3", "p4"]

      # No default patterns, all are optional
      Yast::Packages.stub(:default_patterns).and_return([])
      Yast::Packages.stub(:optional_default_patterns).and_return(optional_default_patterns)
      Yast::Packages.stub(:ComputeSystemPatternList).and_return([])
      Yast::Pkg.stub(:ResolvableProperties).and_return([])

      expect(Yast::Report).not_to receive(:Error)

      expect(Yast::Y2Logger.instance).to receive(:info) do |msg|
        expect(msg).to match(/optional pattern p[3-4] does not exist/i).exactly(4).times
      end.at_least(4).times.and_call_original

      # Called twice with reselect=true/false
      Yast::Packages.SelectSystemPatterns(true)
      Yast::Packages.SelectSystemPatterns(false)
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

  describe "#product_label" do
    let(:product) { load_zypp("products_update.yml").first }

    it "returns display_name if available" do
      expect(Yast::Packages.product_label(product)).to eq("SUSE Linux Enterprise Server 12")
    end

    it "return short_name if display_name is not available" do
      product["display_name"] = ""
      expect(Yast::Packages.product_label(product)).to eq("SLES12")
    end

    it "returns name when both display_name and short_name are not available" do
      product["display_name"] = ""
      product["short_name"] = ""
      expect(Yast::Packages.product_label(product)).to eq("SLES")
    end
  end

  describe "#group_products_by_status" do
    let(:products) { load_zypp("products_update.yml") }
    let(:products2) { load_zypp("products_update2.yml") }

    it "returns groups of the products" do
      status = Yast::Packages.group_products_by_status(products)

      expect(status[:new]).to eq([])

      # no update replacement for SDK, it will be removed
      expect(status[:removed].first["display_name"]).to \
        eq("SUSE Linux Enterprise Software Development Kit 11 SP3")

      expect(status[:kept]).to eq([])

      # update from SLES11-SP3 to SLES12
      expect(status[:updated].size).to eq(1)
      old_product, new_product = status[:updated].first
      expect(old_product["display_name"]).to eq("SUSE Linux Enterprise Server 11 SP3")
      expect(new_product["display_name"]).to eq("SUSE Linux Enterprise Server 12")
    end

    it "returns updated product which has been renamed" do
      products = [
        { "name" => "sle-haegeo", "status" => :removed },
        { "name" => "sle-ha-geo", "status" => :selected }
      ]

      status = Yast::Packages.group_products_by_status(products)

      expect(status[:updated].size).to eq(1)
      old_product, new_product = status[:updated].first
      expect(old_product["name"]).to eq("sle-haegeo")
      expect(new_product["name"]).to eq("sle-ha-geo")
    end

    it "handles mixed renamed and unchanged products" do
      status = Yast::Packages.group_products_by_status(products2)

      expect(status[:new]).to eq([])
      expect(status[:removed]).to eq([])
      expect(status[:kept]).to eq([])
      expect(status[:updated].size).to eq(3)
    end
  end

  describe "#product_update_summary" do
    let(:products) { load_zypp("products_update.yml") }

    it "describes the product update as a human readable summary" do
      summary_string = Yast::Packages.product_update_summary(products).to_s

      expect(summary_string).to match(
        /SUSE Linux Enterprise Server 11 SP3.*will be updated to.*SUSE Linux Enterprise Server 12/)

      expect(summary_string).to match(
        /SUSE Linux Enterprise Software Development Kit 11 SP3.*will be automatically removed/)
    end
  end

  describe "#product_update_warning" do
    let(:products) { load_zypp("products_update.yml") }

    it "returns a hash with warning when there is an automatically removed product" do
      expect(Yast::Packages.product_update_warning(products)).to include("warning", "warning_level")
    end

    it "returns empty hash when there is no automatically removed product" do
      products.each { |product| product["transact_by"] = :user }
      expect(Yast::Packages.product_update_warning(products)).to eq({})
    end
  end

  describe "#ComputeSystemPatternList" do
    before do
      expect(Yast::Arch).to receive(:is_laptop).and_return(false)
      expect(Yast::Arch).to receive(:has_pcmcia).and_return(false)
      expect(Yast::PackagesProposal).to receive(:GetAllResolvables).with(:pattern).and_return([])
    end

    context "when fips pattern is available" do
      before do
        allow(Yast::Pkg).to receive(:ResolvableProperties).
          with("fips", :pattern, "").and_return([{ "name" => "fips" }])
      end

      it "adds 'fips' pattern if fips=1 boot parameter is used" do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("foo fips=1 bar")
        expect(Yast::Packages.ComputeSystemPatternList).to include("fips")
      end

      it "does not add 'fips' pattern if fips=1 boot parameter is not used" do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("foo bar")
        expect(Yast::Packages.ComputeSystemPatternList).to_not include("fips")
      end
    end

    context "when fips pattern is not available" do
      before do
        allow(Yast::Pkg).to receive(:ResolvableProperties).
          with("fips", :pattern, "").and_return([])
      end

      it "does not add 'fips' pattern if fips=1 boot parameter is used" do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("foo fips=1 bar")
        expect(Yast::Packages.ComputeSystemPatternList).to_not include("fips")
      end

      it "does not add 'fips' pattern if fips=1 boot parameter is not used" do
        expect(Yast::Linuxrc).to receive(:InstallInf).with("Cmdline").and_return("foo bar")
        expect(Yast::Packages.ComputeSystemPatternList).to_not include("fips")
      end
    end
  end

  describe "#vnc_packages" do
    let(:packages) { Yast::Packages.vnc_packages.sort.uniq }
    let(:base_packages) { ["xinetd", "xorg-x11", "xorg-x11-Xvnc", "xorg-x11-fonts"] }
    let(:base_packages_and_wm) { ["icewm"] + base_packages }

    context "during installation" do
      before do
        allow(Yast::Pkg).to receive(:IsProvided).and_return false
        allow(Yast::Mode).to receive(:mode).and_return "installation"
      end

      context "with window manager already selected" do
        before do
          allow(Yast::Pkg).to receive(:IsSelected).and_return true
        end

        it "includes xinetd and xorg" do
          expect(packages).to eq(base_packages)
        end
      end

      context "without window manager selected" do
        before do
          allow(Yast::Pkg).to receive(:IsSelected).and_return false
        end

        it "includes xinetd, xorg and icewm" do
          expect(packages).to eq(base_packages_and_wm)
        end
      end
    end

    context "during autoinstallation" do
      before do
        allow(Yast::Pkg).to receive(:IsProvided).and_return false
        allow(Yast::Mode).to receive(:mode).and_return "autoinstallation"
      end

      context "with window manager already selected" do
        before do
          allow(Yast::Pkg).to receive(:IsSelected).and_return true
        end

        it "includes xinetd, xorg and yast2-x11" do
          expect(packages).to eq(base_packages + ["yast2-x11"])
        end
      end

      context "without window manager selected" do
        before do
          allow(Yast::Pkg).to receive(:IsSelected).and_return false
        end

        it "includes xinetd, xorg and icewm" do
          expect(packages).to eq(base_packages_and_wm + ["yast2-x11"])
        end
      end
    end

    context "in normal mode" do
      before do
        allow(Yast::Pkg).to receive(:IsSelected).and_return false
        allow(Yast::Mode).to receive(:mode).and_return "normal"
      end

      context "with window manager already installed" do
        before do
          allow(Yast::Pkg).to receive(:IsProvided).and_return true
        end

        it "includes xinetd and xorg" do
          expect(packages).to eq(base_packages)
        end
      end

      context "without window manager installed" do
        before do
          allow(Yast::Pkg).to receive(:IsProvided).and_return false
        end

        it "includes xinetd, xorg and icewm" do
          expect(packages).to eq(base_packages_and_wm)
        end
      end
    end
  end

  describe "#modePackages" do
    before do
      allow(Yast::Linuxrc).to receive(:vnc).and_return vnc
      allow(Yast::Linuxrc).to receive(:display_ip).and_return display_ip
      allow(Yast::Linuxrc).to receive(:braille).and_return braille
      allow(Yast::Linuxrc).to receive(:usessh).and_return usessh
      allow(Yast::Mode).to receive(:mode).and_return mode
    end
    let(:packages) { Yast::Packages.modePackages.sort.uniq }

    context "on a boring local regular installation" do
      let(:vnc) { false }
      let(:display_ip) { false }
      let(:braille) { false }
      let(:usessh) { false }
      let(:mode) { "installation" }

      it "returns an empty array" do
        expect(packages).to be_empty
      end
    end

    context "over ssh with a remote X server" do
      let(:vnc) { false }
      let(:display_ip) { true }
      let(:braille) { false }
      let(:usessh) { true }
      let(:xorg_icewm_and_ssh) {
        ["icewm", "openssh", "xorg-x11-fonts", "xorg-x11-server"]
      }

      context "during installation" do
        let(:mode) { "installation" }

        it "includes xorg, icewm and openssh" do
          expect(packages).to eq(xorg_icewm_and_ssh)
        end
      end

      context "during autoinstallation" do
        let(:mode) { "autoinstallation" }

        it "includes xorg, icewm, openssh and yast2-x11" do
          expect(packages).to eq(xorg_icewm_and_ssh + ["yast2-x11"])
        end
      end
    end

    context "on vnc installation" do
      let(:vnc) { true }
      let(:display_ip) { false }
      let(:braille) { false }
      let(:usessh) { false }
      let(:mode) { "installation" }

      it "relies on #vnc_packages" do
        expect(Yast::Packages).to receive(:vnc_packages).and_return %w(five names)
        expect(packages).to eq(%w(five names))
      end
    end
  end
end
