#! /usr/bin/env rspec

require_relative "./test_helper"

require "yaml"
require "uri"

Yast.import "Packages"
Yast.import "SCR"
Yast.import "Product"
Yast.import "ProductFeatures"
Yast.import "Linuxrc"
Yast.import "Pkg"

require "packager/product_patterns"

SCR_STRING_PATH = Yast::Path.new(".target.string")
SCR_PROC_CMDLINE_PATH = Yast::Path.new(".proc.cmdline")

CHECK_FOR_DELL_SYSTEM = Regexp.new(
  "hwinfo .*bios .*grep .*vendor:.*dell inc",
  Regexp::IGNORECASE
)

def load_zypp(file_name)
  file_name = File.join(DATA_PATH, "zypp", file_name)
  Yast.y2milestone "Loading file: #{file_name}"
  YAML.load_file(file_name)
end

def product_from_zypp
  load_zypp("products.yml").map {|p| Y2Packager::Resolvable.new(p)}
end

PRODUCTS_FROM_ZYPP = load_zypp("products.yml").freeze

describe Yast::Packages do
  subject { Yast::Packages }
  before(:each) do
    Yast.y2milestone "--- test ---"
  end

  describe "#kernelCmdLinePackages" do
    before(:each) do
      # default value
      allow(Yast::Product).to receive(:Product).and_return nil
    end

    context "when biosdevname behavior explicitly defined on the Kenel command line" do
      context "when biosdevname=1" do
        around do |example|
          root = File.join(DATA_PATH, "cmdline-biosdevname_1")
          change_scr_root(root, &example)
        end

        it "returns biosdevname within the list of required packages" do
          expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to eq(true)
        end
      end

      context "when biosdevname=0" do
        around do |example|
          root = File.join(DATA_PATH, "cmdline-biosdevname_0")
          change_scr_root(root, &example)
        end

        it "does not return biosdevname within the list of required packages" do
          expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to eq(false)
        end
      end

      context "when biosdevname=10 (invalid)" do
        around do |example|
          root = File.join(DATA_PATH, "cmdline-biosdevname_10")
          change_scr_root(root, &example)
        end

        it "does not return biosdevname within the list of required packages" do
          expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to eq(false)
        end
      end
    end

    context "when no /proc/cmdline is defined" do
      it "returns empty list when a Dell system is not detected" do
        expect(Yast::SCR).to receive(:Read).with(SCR_PROC_CMDLINE_PATH).and_return(nil)
        expect(Yast::Packages).to receive(:DellSystem).and_return(false)
        expect(Yast::Packages.kernelCmdLinePackages).to eq([])
      end

      it "returns biosdevname package when a Dell system is detected" do
        expect(Yast::SCR).to receive(:Read).with(SCR_PROC_CMDLINE_PATH).and_return(nil)
        expect(Yast::Packages).to receive(:DellSystem).and_return(true)
        expect(Yast::Packages.kernelCmdLinePackages).to eq(["biosdevname"])
      end
    end

    context "when biosdevname behavior not defined on the Kernel command line" do
      around do |example|
        root = File.join(DATA_PATH, "cmdline-biosdevname_nil")
        change_scr_root(root, &example)
      end

      context "and running on a Dell system" do
        it "returns biosdevname within the list of packages" do
          # 0 means `grep` succeeded
          allow(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH, CHECK_FOR_DELL_SYSTEM)
            .and_return(0)
          expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to eq(true)
        end
      end

      context "and running on a non-Dell system" do
        it "does not return biosdevname within the list of packages" do
          # 1 means `grep` has not succeeded
          allow(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH, CHECK_FOR_DELL_SYSTEM)
            .and_return(1)
          expect(Yast::Packages.kernelCmdLinePackages.include?("biosdevname")).to eq(false)
        end
      end
    end

  end

  describe "#default_patterns" do
    context "software->default_patterns is not defined in control file" do
      it "returns empty list" do
        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("software", "default_patterns").and_return("")
        expect(Yast::Packages.default_patterns).to be_empty
      end
    end

    context "software->default_patterns is filled with list of patterns" do
      it "returns list of patterns" do
        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("software", "default_patterns").and_return("a b c d")
        expect(Yast::Packages.default_patterns).to eq(["a", "b", "c", "d"])

        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("software", "default_patterns").and_return("  a    b\t c d\t  ")
        expect(Yast::Packages.default_patterns).to eq(["a", "b", "c", "d"])

        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("software", "default_patterns").and_return("  a b \n c\nd  ")
        expect(Yast::Packages.default_patterns).to eq(["a", "b", "c", "d"])
      end
    end
  end

  describe "#optional_default_patterns" do
    context "software->optional_default_patterns is not defined in control file" do
      it "returns empty list" do
        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("software", "optional_default_patterns").and_return("")
        expect(Yast::Packages.optional_default_patterns).to be_empty
      end
    end

    context "software->optional_default_patterns is filled with list of patterns" do
      it "returns list of patterns" do
        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("software", "optional_default_patterns").and_return("a b c d")
        expect(Yast::Packages.optional_default_patterns).to eq(["a", "b", "c", "d"])

        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("software", "optional_default_patterns").and_return("  a    b\t c d\t  ")
        expect(Yast::Packages.optional_default_patterns).to eq(["a", "b", "c", "d"])

        allow(Yast::ProductFeatures).to receive(:GetStringFeature)
          .with("software", "optional_default_patterns").and_return("  a b \n c\nd  ")
        expect(Yast::Packages.optional_default_patterns).to eq(["a", "b", "c", "d"])
      end
    end
  end

  DEFAULT_PATTERN = {
    "kind"        => :pattern,
    "name"        => "name",
    "version"     => "1.0.0",
    "arch"        => "x86_64",
    "source"      => 1,
    "summary"     => "",
    "status"      => :available,
    "transact_by" => :app_high
  }.freeze

  def pattern(properties = {})
    Y2Packager::Resolvable.new(DEFAULT_PATTERN.merge(properties))
  end

  DEFAULT_PRODUCT = {
    "kind"        => :product,
    "name"        => "name",
    "version"     => "1.0.0",
    "arch"        => "x86_64",
    "source"      => 1,
    "summary"     => "",
    "status"      => :available,
    "transact_by" => :app_high
  }.freeze

  def product(properties = {})
    Y2Packager::Resolvable.new(DEFAULT_PRODUCT.merge(properties))
  end

  DEFAULT_PACKAGE = {
    "kind"        => :package,
    "name"        => "name",
    "version"     => "1.0.0",
    "arch"        => "x86_64",
    "source"      => 1,
    "summary"     => "",
    "status"      => :available,
    "transact_by" => :app_high
  }.freeze

  def package(properties = {})
    Y2Packager::Resolvable.new(DEFAULT_PACKAGE.merge(properties))
  end

  describe "#SelectSystemPatterns" do
    context "if this is the initial run or it is being reinitialized" do
      context "and patterns are not unselected by user" do
        it "selects patterns for installation" do
          allow(Yast::Packages).to receive(:patterns_to_install).and_return(["p1", "p2", "p3"])
          allow(Y2Packager::Resolvable).to receive(:find).and_return(
            [pattern("name" => "p1")],
            [pattern("name" => "p2")],
            [pattern("name" => "p3")]
          )

          allow(Yast::Pkg).to receive(:ResolvableInstall).with(/\Ap[1-3]/, :pattern)
            .exactly(3).times.and_return(true)
          Yast::Packages.SelectSystemPatterns(false)
        end
      end

      context "and some patterns are already unselected by user" do
        it "selects patterns for installation that were not unselected by user already" do
          allow(Yast::Packages).to receive(:patterns_to_install).and_return(["p1", "p2", "p3"])
          allow(Y2Packager::Resolvable).to receive(:find).and_return(
            [pattern("name" => "p1", "transact_by" => :user)],
            [pattern("name" => "p2", "transact_by" => :user)],
            [pattern("name" => "p3")]
          )

          expect(Yast::Pkg).not_to receive(:ResolvableInstall).with("p1", :pattern)
          expect(Yast::Pkg).not_to receive(:ResolvableInstall).with("p2", :pattern)
          expect(Yast::Pkg).to receive(:ResolvableInstall).with("p3", :pattern).once
            .and_return(true)
          Yast::Packages.SelectSystemPatterns(false)
        end
      end
    end

    context "if this is a subsequent run" do
      it "re-selects all patterns already selected for installation" do
        allow(Yast::Packages).to receive(:patterns_to_install).and_return(["p1", "p2", "p3"])
        allow(Y2Packager::Resolvable).to receive(:find).and_return(
          [pattern("name" => "p1", "transact_by" => :user, "status" => :selected)],
          [pattern("name" => "p2", "transact_by" => :user, "status" => :selected)],
          [pattern("name" => "p3")]
        )

        expect(Yast::Pkg).to receive(:ResolvableRemove).with(/\Ap[1-2]/, :pattern).twice
          .and_return(true)
        expect(Yast::Pkg).not_to receive(:ResolvableInstall).with("p3", :pattern)
        Yast::Packages.SelectSystemPatterns(true)
      end
    end

    it "reports an error if pattern is not found" do
      default_patterns = ["p1", "p2"]
      optional_default_patterns = ["p5", "p6"]

      allow(Yast::Packages).to receive(:default_patterns).and_return(default_patterns)
      allow(Yast::Packages).to receive(:optional_default_patterns)
        .and_return(optional_default_patterns)
      allow(Yast::Packages).to receive(:patterns_to_install).and_return(default_patterns)
      allow(Y2Packager::Resolvable).to receive(:find).and_return([])
      allow(Yast::Report).to receive(:Error).and_return(nil)

      # Called twice with reselect=true/false
      Yast::Packages.SelectSystemPatterns(true)
      Yast::Packages.SelectSystemPatterns(false)

      expect(Yast::Report).to have_received(:Error).with(/patterns:\np1, p2\n/i)
        .exactly(2).times
    end

    it "does not report an error but logs it if optional pattern is not found" do
      optional_default_patterns = ["p3", "p4"]

      # No default patterns, all are optional
      allow(Yast::Packages).to receive(:default_patterns).and_return([])
      allow(Yast::Packages).to receive(:optional_default_patterns)
        .and_return(optional_default_patterns)
      allow(Yast::Packages).to receive(:ComputeSystemPatternList)
        .and_return(optional_default_patterns)
      allow(Y2Packager::Resolvable).to receive(:find).and_return([])

      expect(Yast::Report).not_to receive(:Error)

      logged_errors = 0
      allow(Yast::Y2Logger.instance).to receive(:info) do |msg|
        logged_errors += 1 if msg =~ /optional pattern p[3-4] does not exist/i
      end

      # Called twice with reselect=true/false
      Yast::Packages.SelectSystemPatterns(true)
      Yast::Packages.SelectSystemPatterns(false)

      expect(logged_errors).to eq 4
    end

    it "selects the default product patterns" do
      allow(Yast::Packages).to receive(:ComputeSystemPatternList).and_return([])
      allow(Yast::Packages).to receive(:default_patterns).and_return([])
      allow(Yast::Packages).to receive(:optional_default_patterns).and_return([])
      allow(Y2Packager::Resolvable).to receive(:find).and_return([pattern()])

      product_patterns = ["default_pattern_1", "default_pattern_2"]
      expect_any_instance_of(Yast::ProductPatterns).to receive(:names).at_least(:once)
        .and_return(product_patterns)
      expect(Yast::Pkg).to receive(:ResolvableInstall).with(product_patterns[0], :pattern)
      expect(Yast::Pkg).to receive(:ResolvableInstall).with(product_patterns[1], :pattern)

      Yast::Packages.SelectSystemPatterns(false)
    end

    it "raises if the actions helper uses an unknown action" do
      allow(Yast::Packages).to receive(:patterns_to_install).and_return(["p1", "p2", "p3"])
      expect(Yast::Packages).to receive(:select_system_patterns_actions)
        .and_return([
                      ["p1", :surprise],
                      ["p2", :install],
                      ["p3", :install]
                    ])
      expect { Yast::Packages.SelectSystemPatterns(false) }.to raise_error(ArgumentError)
    end

    # private helper
    describe "#report_missing_patterns" do
      it "does nothing for an empty list" do
        expect(Yast::Report).not_to receive(:Error)
        Yast::Packages.send(:report_missing_patterns, [])
      end

      it "formats the list of patterns" do
        ps = ["p1", "p2", "p3", "p4", "p5", "p6",
              "p7", "p8", "p9", "p10", "p11", "p12"]
        formatted = /patterns:\np1, p2, p3, p4, p5,\np6, p7, p8, p9, p10,\np11, p12\n/
        expect(Yast::Report).to receive(:Error).with(formatted)
        Yast::Packages.send(:report_missing_patterns, ps)
      end
    end
  end

  describe "#log_software_selection" do
    it "logs all currently changed resolvables set by user or application (excluding solver)" do
      allow(Y2Packager::Resolvable).to receive(:find).and_return([])
      allow(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
        .and_return(product_from_zypp)

      expect(Yast::Y2Logger.instance).to receive(:info) do |msg|
        expect(msg).to match(
          /(transaction\sstatus\s[begin|end]|(locked)?resolvables\s
           of\stype\s.*\sset\sby\s.*|:name=>.*:version=>)/ix
        )
      end.exactly(8).times

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
    let(:smt_products) { load_zypp("products_update_smt.yml") }

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
      hae = { "name" => "sle-hae", "status" => :removed }
      ha = { "name" => "sle-ha", "status" => :selected }
      products = [hae, ha]

      status = Yast::Packages.group_products_by_status(products)

      updates = status[:updated]
      expect(updates.size).to eq(1)

      # check the HAE => HA rename
      expect(updates[hae]).to eq(ha)
    end

    it "returns updated products which have been merged" do
      hae = { "name" => "sle-hae", "status" => :removed }
      haegeo = { "name" => "sle-haegeo", "status" => :removed }
      ha = { "name" => "sle-ha", "status" => :selected }
      products = [hae, haegeo, ha]

      status = Yast::Packages.group_products_by_status(products)

      # product updates
      updates = status[:updated]
      expect(updates.size).to eq(2)

      # check the HAE => HA rename
      expect(updates[hae]).to eq(ha)
      # check the HAE GEO => HA merge
      expect(updates[haegeo]).to eq(ha)
    end

    it "handles mixed renamed and unchanged products" do
      status = Yast::Packages.group_products_by_status(products2)

      expect(status[:new]).to eq([])
      expect(status[:removed]).to eq([])
      expect(status[:kept]).to eq([])
      expect(status[:updated].size).to eq(3)
    end

    it "handles multiple products updated to a single product" do
      status = Yast::Packages.group_products_by_status(smt_products)

      expect(status[:new]).to eq([])
      expect(status[:removed]).to eq([])
      expect(status[:kept]).to eq([])
      expect(status[:updated].size).to eq(2)
    end
  end

  describe "#product_update_summary" do
    let(:products) { load_zypp("products_update.yml") }
    let(:suma_products_map) { load_zypp("products_update_suma_branch_server.yml") }
    let(:suma_products) { suma_products_map.map do |p|
                            p["kind"] = :product
                            Y2Packager::Resolvable.new(p)
                          end }

    before do
      allow(Y2Packager::ProductUpgrade).to receive(:will_be_obsoleted_by).and_return([])
    end

    it "describes the product update as a human readable summary" do
      summary_string = Yast::Packages.product_update_summary(products).to_s

      expect(summary_string).to match(
        /SUSE Linux Enterprise Server 11 SP3.*will be updated to.*SUSE Linux Enterprise Server 12/
      )

      expect(summary_string).to match(
        /SUSE Linux Enterprise Software Development Kit 11 SP3.*will be automatically removed/
      )
    end

    it "handles multiple products updated to a single product" do
      smt_update = load_zypp("products_update_smt.yml")
      summary_string = Yast::Packages.product_update_summary(smt_update).to_s

      expect(summary_string).to match(
        /SUSE Linux Enterprise Server 11 SP3.*will be updated to.*SUSE Linux Enterprise Server 12/
      )

      expect(summary_string).to match(
        /Subscription\sManagement\sTool\sfor\sSUSE\sLinux\sEnterprise\s11\sSP3.*
         will\sbe\supdated\sto.*SUSE\sLinux\sEnterprise\sServer\s12/x
      )
    end

    # test conversion of the internal product name "SUSE-Manager-Retail-Branch-Server" to
    # human readable text "SUSE Manager Retail Branch Server 4.0"
    it "converts obsolete product identifiers to human readable names" do
      allow(Y2Packager::ProductUpgrade).to receive(:will_be_obsoleted_by).with("SLES")
        .and_return(["SUSE-Manager-Retail-Branch-Server"])
      allow(Y2Packager::ProductUpgrade).to receive(:will_be_obsoleted_by).with("SUSE-Manager-Proxy")
        .and_return(["SUSE-Manager-Retail-Branch-Server"])
      allow(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
        .and_return(suma_products)
      expect(Y2Packager::Resolvable).to receive(:find).with(kind: :package, name: /sle/ )
        .and_return([])
      allow(Y2Packager::Product).to receive(:with_status).with(:selected).and_return(
        suma_products_map.select { |p| p["status"] == :selected }
        .map { |p| Y2Packager::Product.from_h(p) }
      )

      summary_string = Yast::Packages.product_update_summary(suma_products_map).to_s

      # just to make the lines shorter
      rbs = "SUSE Manager Retail Branch Server"
      # SLES is removed from the system, but it is actually replaced by the SUMA Branch Server
      # (which is additionally upgraded to version 4.0)
      expect(summary_string).to match(
        /SUSE Linux Enterprise Server 12 SP3.* will be updated to .*#{rbs} 4\.0/
      )
      # SUMA Proxy is removed from the system, but it is actually replaced by the SUMA Branch Server
      # (which is additionally upgraded to version 4.0)
      expect(summary_string).to match(
        /SUSE Manager Proxy 3\.2.*will be updated to.*#{rbs} 4\.0/
      )
      # SUSE Manager Retail Branch Server is upgraded to version 4.0
      expect(summary_string).to match(
        /SUSE Manager Retail Branch Server 3\.2.*will be updated to.*#{rbs} 4\.0/
      )
    end
  end

  describe "#product_update_warning" do
    let(:products) { load_zypp("products_update.yml") }

    context "product will be removed due an obsolete" do
      before do
        allow(Y2Packager::ProductUpgrade).to receive(:will_be_obsoleted_by)
          .and_return(["new_product"])
      end

      it "returns empty hash" do
        expect(Yast::Packages.product_update_warning(products)).to eq({})
      end
    end

    context "product will be removed" do
      before do
        allow(Y2Packager::ProductUpgrade).to receive(:will_be_obsoleted_by).and_return([])
      end

      it "returns a hash with warning when there is an automatically removed product" do
        expect(Yast::Packages.product_update_warning(products)).to include("warning",
          "warning_level")
      end

      it "returns empty hash when there is no automatically removed product" do
        products.each { |product| product["transact_by"] = :user }
        expect(Yast::Packages.product_update_warning(products)).to eq({})
      end
    end

    context "SUSE Manager 3.2 upgrade" do
      # upgrade SLES12-SP3 + SUMA-3.2 to SLE15-SP1 (actually SUMA 4.0)
      let(:suma_products_map) { load_zypp("products_update_suma.yml") }
      let(:suma_products) { suma_products_map.map {|p| Y2Packager::Resolvable.new(p)} }

      before do
        allow(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
          .and_return(suma_products)

        suma_products.map { |p| p.name }.uniq.each do |prod_name|
          allow(Y2Packager::Resolvable).to receive(:find).with(name: prod_name, kind: :product)
            .and_return(suma_products.select { |p| p.name == prod_name })
        end
      end

      # the SLES12-SP3 is replaced by the SUMA base product,
      # do not complain for the automatic SLES removal
      it "does not report any upgrade problem" do
        expect(Yast::Packages.product_update_warning(suma_products_map)).to eq({})
      end
    end
  end

  describe "#ComputeSystemPatternList" do
    before do
      expect(Yast::Arch).to receive(:is_laptop).and_return(false)
      expect(Yast::Arch).to receive(:has_pcmcia).and_return(false)
      expect(Yast::PackagesProposal).to receive(:GetAllResolvables).with(:pattern).and_return([])
      expect(Yast::PackagesProposal).to receive(:GetAllResolvables).with(:pattern, optional: true)
        .and_return([])
    end

    context "when fips pattern is available" do
      before do
        allow_any_instance_of(Yast::ProductPatterns).to receive(:names).and_return([])
        allow(Y2Packager::Resolvable).to receive(:find)
          .with(name: "fips", kind: :pattern).and_return([pattern({ "name" => "fips" })])
      end

      it "adds 'fips' pattern if the FIPS mode is active" do
        expect(File).to receive(:exist?).with("/proc/sys/crypto/fips_enabled").and_return(true)
        expect(File).to receive(:read).with("/proc/sys/crypto/fips_enabled").and_return("1\n")
        expect(Yast::Packages.ComputeSystemPatternList).to include("fips")
      end

      it "does not add 'fips' pattern if the FIPS mode is not active" do
        expect(File).to receive(:exist?).with("/proc/sys/crypto/fips_enabled").and_return(true)
        expect(File).to receive(:read).with("/proc/sys/crypto/fips_enabled").and_return("0\n")
        expect(Yast::Packages.ComputeSystemPatternList).to_not include("fips")
      end

      it "does not add 'fips' pattern if the FIPS mode is not supported" do
        expect(File).to receive(:exist?).with("/proc/sys/crypto/fips_enabled").and_return(false)
        expect(Yast::Packages.ComputeSystemPatternList).to_not include("fips")
      end
    end

    context "when fips pattern is not available" do
      before do
        allow_any_instance_of(Yast::ProductPatterns).to receive(:names).and_return([])
        allow(Y2Packager::Resolvable).to receive(:find)
          .with(name: "fips", kind: :pattern).and_return([])
        allow(Yast::Report).to receive(:Error)
      end

      context "kernel does not support the FIPS mode" do
        before do
          expect(File).to receive(:exist?).with("/proc/sys/crypto/fips_enabled").and_return(false)
        end

        it "does not report an error if the FIPS mode is not supported" do
          expect(Yast::Report).to_not receive(:Error)
          Yast::Packages.ComputeSystemPatternList
        end
      end

      context "kernel supports the FIPS mode" do
        before do
          expect(File).to receive(:exist?).with("/proc/sys/crypto/fips_enabled").and_return(true)
        end

        it "does not report an error if the FIPS mode is not active" do
          expect(File).to receive(:read).with("/proc/sys/crypto/fips_enabled").and_return("0\n")
          expect(Yast::Report).to_not receive(:Error)
          Yast::Packages.ComputeSystemPatternList
        end

        it "reports an error if the FIPS mode is active" do
          expect(File).to receive(:read).with("/proc/sys/crypto/fips_enabled").and_return("1\n")
          expect(Yast::Report).to receive(:Error).with(/the 'fips' pattern is not available/)
          Yast::Packages.ComputeSystemPatternList
        end

        it "does not add 'fips' pattern if the FIPS mode is active" do
          expect(File).to receive(:read).with("/proc/sys/crypto/fips_enabled").and_return("1\n")
          expect(Yast::Packages.ComputeSystemPatternList).to_not include("fips")
        end
      end
    end
  end

  describe "#vnc_packages" do
    let(:packages) { Yast::Packages.vnc_packages.sort.uniq }
    let(:base_packages) { ["xorg-x11", "xorg-x11-Xvnc", "xorg-x11-fonts"] }
    let(:base_packages_and_wm) { ["icewm"] + base_packages }
    let(:autoyast_x11_packages) { ["libyui-qt6", "yast2-x11"] }

    before do
      (base_packages_and_wm + ["yast2-x11"]).each do |pkg|
        allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg).and_return([[pkg, :CAND, :NONE]])
      end
      allow(Yast::Pkg).to receive(:PkgQueryProvides).with("libyui-qt")
        .and_return([["libyui-qt6", :CAND, :NONE]])
    end

    context "during installation" do
      before do
        allow(Yast::Pkg).to receive(:IsProvided).and_return false
        allow(Yast::Mode).to receive(:mode).and_return "installation"
      end

      context "with window manager already selected" do
        before do
          allow(Yast::Pkg).to receive(:IsSelected).and_return true
        end

        it "includes xorg" do
          expect(packages).to eq(base_packages)
        end
      end

      context "without window manager selected" do
        before do
          allow(Yast::Pkg).to receive(:IsSelected).and_return false
        end

        it "includes xorg and icewm" do
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

        it "includes xorg and autoyast X11 packages" do
          expected = (base_packages + autoyast_x11_packages).sort
          expect(packages).to eq(expected)
        end
      end

      context "without window manager selected" do
        before do
          allow(Yast::Pkg).to receive(:IsSelected).and_return false
        end

        it "includes xorg and icewm" do
          expected = (base_packages_and_wm + autoyast_x11_packages).sort
          expect(packages).to eq(expected)
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

        it "includes xorg" do
          expect(packages).to eq(base_packages)
        end
      end

      context "without window manager installed" do
        before do
          allow(Yast::Pkg).to receive(:IsProvided).and_return false
        end

        it "includes xorg and icewm" do
          expect(packages).to eq(base_packages_and_wm)
        end
      end
    end

    context "when some package is missing" do
      let(:package) { "missing-pkg" }

      before do
        stub_const("Yast::PackagesClass::VNC_BASE_TAGS", [package])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(package).and_return([])
      end

      it "includes the tag name in the packages list but logs an error" do
        expect(Yast::Packages.log).to receive(:error).with("Provider not found for '#{package}'")
        expect(subject.vnc_packages).to include(package)
      end
    end

    context "when some package is not available" do
      let(:package) { "unavailable-pkg" }

      before do
        stub_const("Yast::PackagesClass::VNC_BASE_TAGS", [package])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(package).and_return([[package, :NONE, :NONE]])
      end

      it "includes the tag name in the packages list but logs an error" do
        expect(Yast::Packages.log).to receive(:error).with("Provider not found for '#{package}'")
        expect(subject.vnc_packages).to include(package)
      end
    end

    context "when more than one package provides a tag" do
      let(:package) { "multi-provider-pkg" }

      before do
        stub_const("Yast::PackagesClass::VNC_BASE_TAGS", [package])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(package).and_return(providers.map { |n| [n, :CAND, :NONE] })
      end

      context "when a package named after the tag is found" do
        let(:providers) { ["prov1", package] }

        it "includes the tag as package name and logs a message" do
          expect(Yast::Packages.log).to receive(:warn)
            .with("More than one provider was found for '#{package}': " \
                 "prov1, #{package}. Selecting '#{package}'.")
          expect(subject.vnc_packages).to include(package)
        end
      end

      context "when a package named after the tag is not found" do
        let(:providers) { ["prov2", "prov1"] }

        it "includes the first provider (according to alphabetic order) and logs a message" do
          expect(Yast::Packages.log).to receive(:warn)
            .with("More than one provider was found for '#{package}': " \
                 "prov2, prov1. Selecting 'prov1'.")
          expect(subject.vnc_packages).to include("prov1")
        end
      end
    end

    context "when a package is installed and have also a valid candidate (:BOTH)" do
      let(:tag) { "some-tag" }
      let(:providers) { [["prov1", :CAND, :NONE], ["prov2", :BOTH, :INST]] }

      before do
        stub_const("Yast::PackagesClass::VNC_BASE_TAGS", [tag])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(tag).and_return(providers)
      end

      it "the yet installed package must be preferred" do
        expect(subject.vnc_packages).to include("prov2")
      end
    end

    context "when a package is installed but a valid candidate exists" do
      let(:tag) { "some-tag" }
      let(:providers) { [["prov1", :INST, :INST], ["prov2", :CAND, :NONE]] }

      before do
        stub_const("Yast::PackagesClass::VNC_BASE_TAGS", [tag])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(tag).and_return(providers)
      end

      it "the candidate must be preferred" do
        expect(subject.vnc_packages).to include("prov2")
      end
    end

    context "when a package is installed but no valid candidate" do
      let(:tag) { "some-tag" }
      let(:providers) { [["prov1", :INST, :INST]] }

      before do
        stub_const("Yast::PackagesClass::VNC_BASE_TAGS", [tag])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(tag).and_return(providers)
      end

      it "that installed package is ignored and an error is logged" do
        expect(Yast::Packages.log).to receive(:error).with("Provider not found for '#{tag}'")
        expect(subject.vnc_packages).to include(tag)
      end
    end
  end

  describe "#remote_x11_packages" do
    let(:packages) { Yast::Packages.remote_x11_packages.sort.uniq }
    let(:base_packages) { ["icewm", "xorg-x11-fonts", "xorg-x11-server"] }
    let(:autoyast_x11_packages) { ["libyui-qt6", "yast2-x11"] }

    before do
      (base_packages + ["yast2-x11"]).each do |pkg|
        allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg).and_return([[pkg, :CAND, :NONE]])
      end
      allow(Yast::Pkg).to receive(:PkgQueryProvides).with("libyui-qt")
        .and_return([["libyui-qt6", :CAND, :NONE]])
    end

    context "during installation" do
      before do
        allow(Yast::Pkg).to receive(:IsProvided).and_return false
        allow(Yast::Mode).to receive(:mode).and_return "installation"
      end

      it "includes xorg and icewm" do
        expect(packages).to eq(base_packages)
      end
    end

    context "during autoinstallation" do
      before do
        allow(Yast::Pkg).to receive(:IsProvided).and_return false
        allow(Yast::Mode).to receive(:mode).and_return "autoinstallation"
      end

      it "includes xorg, icewm, libyui-qt and yast2-x11" do
        expect(packages).to eq((base_packages + autoyast_x11_packages).sort)
      end
    end

    context "in normal mode" do
      before do
        allow(Yast::Mode).to receive(:mode).and_return "normal"
      end

      it "includes xorg and icewm" do
        expect(packages).to eq(base_packages)
      end
    end

    context "when some package is missing" do
      let(:package) { "missing-pkg" }

      before do
        stub_const("Yast::PackagesClass::REMOTE_X11_BASE_TAGS", [package])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(package).and_return([])
      end

      it "includes the tag name in the packages list but logs an error" do
        expect(Yast::Packages.log).to receive(:error).with("Provider not found for '#{package}'")
        expect(subject.remote_x11_packages).to include(package)
      end
    end

    context "when some package is not available" do
      let(:package) { "unavailable-pkg" }

      before do
        stub_const("Yast::PackagesClass::REMOTE_X11_BASE_TAGS", [package])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(package).and_return([[package, :NONE, :NONE]])
      end

      it "includes the tag name in the packages list but logs an error" do
        expect(Yast::Packages.log).to receive(:error).with("Provider not found for '#{package}'")
        expect(subject.remote_x11_packages).to include(package)
      end
    end

    context "when more than one package provides a tag" do
      let(:package) { "multi-provider-pkg" }

      before do
        stub_const("Yast::PackagesClass::REMOTE_X11_BASE_TAGS", [package])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(package).and_return(providers.map { |n| [n, :CAND, :NONE] })
      end

      context "when a package named after the tag is found" do
        let(:providers) { ["prov1", package] }

        it "includes the tag as package name and logs a message" do
          expect(Yast::Packages.log).to receive(:warn)
            .with("More than one provider was found for '#{package}': " \
                 "prov1, #{package}. Selecting '#{package}'.")
          expect(subject.remote_x11_packages).to include(package)
        end
      end

      context "when a package named after the tag is not found" do
        let(:providers) { ["prov2", "prov1"] }

        it "includes the first provider (according to alphabetic order) and logs a message" do
          expect(Yast::Packages.log).to receive(:warn)
            .with("More than one provider was found for '#{package}': " \
                 "prov2, prov1. Selecting 'prov1'.")
          expect(subject.remote_x11_packages).to include("prov1")
        end
      end
    end

    context "when a package is installed and have also a valid candidate (:BOTH)" do
      let(:tag) { "some-tag" }
      let(:providers) { [["prov1", :CAND, :NONE], ["prov2", :BOTH, :INST]] }

      before do
        stub_const("Yast::PackagesClass::REMOTE_X11_BASE_TAGS", [tag])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(tag).and_return(providers)
      end

      it "the yet installed package must be preferred" do
        expect(subject.remote_x11_packages).to include("prov2")
      end
    end

    context "when a package is installed but a valid candidate exists" do
      let(:tag) { "some-tag" }
      let(:providers) { [["prov1", :INST, :INST], ["prov2", :CAND, :NONE]] }

      before do
        stub_const("Yast::PackagesClass::REMOTE_X11_BASE_TAGS", [tag])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(tag).and_return(providers)
      end

      it "the candidate must be preferred" do
        expect(subject.remote_x11_packages).to include("prov2")
      end
    end

    context "when a package is installed but no valid candidate" do
      let(:tag) { "some-tag" }
      let(:providers) { [["prov1", :INST, :INST]] }

      before do
        stub_const("Yast::PackagesClass::REMOTE_X11_BASE_TAGS", [tag])
        allow(Yast::Pkg).to receive(:PkgQueryProvides)
          .with(tag).and_return(providers)
      end

      it "that installed package is ignored and an error is logged" do
        expect(Yast::Packages.log).to receive(:error).with("Provider not found for '#{tag}'")
        expect(subject.remote_x11_packages).to include(tag)
      end
    end
  end

  describe "#modePackages" do
    before do
      allow(Yast::Linuxrc).to receive(:vnc).and_return vnc
      allow(Yast::Linuxrc).to receive(:display_ip).and_return display_ip
      allow(Yast::Linuxrc).to receive(:braille).and_return braille
      allow(Yast::Linuxrc).to receive(:usessh).and_return usessh
      allow(Yast::Packages).to receive(:vnc_packages).and_return(vnc_packages)
      allow(Yast::Packages).to receive(:remote_x11_packages).and_return(remote_x11_packages)
      (braille_packages + ssh_packages).each do |pkg|
        allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg).and_return([[pkg, :CAND, :NONE]])
      end
    end

    let(:packages) { Yast::Packages.modePackages.sort.uniq }
    let(:vnc_packages) { %w[some-vnc-packages] }
    let(:remote_x11_packages) { %w[some-x11-packages] }
    let(:ssh_packages) { %w[openssh iproute2] }
    let(:braille_packages) { %w[sbl] }

    context "on a boring local regular installation" do
      let(:vnc) { false }
      let(:display_ip) { false }
      let(:braille) { false }
      let(:usessh) { false }

      it "returns an empty array" do
        expect(packages).to be_empty
      end
    end

    context "on a installation with braille enabled" do
      let(:vnc) { false }
      let(:display_ip) { false }
      let(:braille) { true }
      let(:usessh) { false }

      it "includes braille packages" do
        expect(packages).to eq(braille_packages)
      end
    end

    context "over ssh with a remote X server" do
      let(:vnc) { false }
      let(:display_ip) { true }
      let(:braille) { false }
      let(:usessh) { true }

      it "includes x11 and ssh packages" do
        expected = (remote_x11_packages + ssh_packages).sort
        expect(packages).to eq(expected)
      end
    end

    context "on vnc installation" do
      let(:vnc) { true }
      let(:display_ip) { false }
      let(:braille) { false }
      let(:usessh) { false }

      it "includes vnc packages" do
        expect(packages).to eq(vnc_packages)
      end
    end
  end

  describe "#check_remote_installation_packages" do
    before do
      allow(Yast::Linuxrc).to receive(:vnc).and_return vnc
      allow(Yast::Linuxrc).to receive(:display_ip).and_return display_ip
      allow(Yast::Linuxrc).to receive(:braille).and_return braille
      allow(Yast::Linuxrc).to receive(:usessh).and_return usessh
      allow(Yast::Packages).to receive(:vnc_packages).and_return(vnc_packages)
      allow(Yast::Packages).to receive(:remote_x11_packages).and_return(remote_x11_packages)
      allow(Yast::Packages).to receive(:ssh_packages).and_return(ssh_packages)
      allow(Yast::Packages).to receive(:braille_packages).and_return(braille_packages)
    end

    let(:vnc_packages) { %w[some-vnc-packages] }
    let(:remote_x11_packages) { %w[some-x11-packages] }
    let(:ssh_packages) { %w[openssh iproute2] }
    let(:braille_packages) { %w[sbl] }

    context "on a boring local regular installation" do
      let(:vnc) { false }
      let(:display_ip) { false }
      let(:braille) { false }
      let(:usessh) { false }

      it "reports no error" do
        expect(Yast::Packages.check_remote_installation_packages).to be_empty
        expect(Yast::Packages.missing_remote_packages).to be_empty
        expect(Yast::Packages.missing_remote_kind).to be_empty
      end
    end

    context "on a installation with braille enabled" do
      let(:vnc) { false }
      let(:display_ip) { false }
      let(:braille) { true }
      let(:usessh) { false }

      context "needed packages are available" do
        before do
          braille_packages.each do |pkg|
            allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg)
              .and_return([[pkg, :CAND, :CAND]])
          end
        end

        it "reports no error" do
          expect(Yast::Packages.check_remote_installation_packages).to be_empty
          expect(Yast::Packages.missing_remote_packages).to be_empty
          expect(Yast::Packages.missing_remote_kind).to be_empty
        end
      end

      context "needed packages are not available" do
        before do
          braille_packages.each do |pkg|
            allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg)
              .and_return([[pkg, :CAND, :NONE]])
          end
        end

        it "reports error" do
          expect(Yast::Packages.check_remote_installation_packages).to_not be_empty
          expect(Yast::Packages.missing_remote_packages).to eq(braille_packages)
          expect(Yast::Packages.missing_remote_kind).to eq(["BRAILLE"])
        end
      end
    end

    context "over ssh with a remote X server" do
      let(:vnc) { false }
      let(:display_ip) { true }
      let(:braille) { false }
      let(:usessh) { true }

      context "needed packages are available" do
        before do
          (remote_x11_packages + ssh_packages).each do |pkg|
            allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg)
              .and_return([[pkg, :CAND, :CAND]])
          end
        end

        it "reports no error" do
          expect(Yast::Packages.check_remote_installation_packages).to be_empty
          expect(Yast::Packages.missing_remote_packages).to be_empty
          expect(Yast::Packages.missing_remote_kind).to be_empty
        end
      end

      context "only ssh packages are available" do
        before do
          ssh_packages.each do |pkg|
            allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg)
              .and_return([[pkg, :CAND, :NONE]])
          end
          remote_x11_packages.each do |pkg|
            allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg)
              .and_return([[pkg, :CAND, :CAND]])
          end
        end

        it "reports error for X11 packages" do
          expect(Yast::Packages.check_remote_installation_packages).to_not be_empty
          expect(Yast::Packages.missing_remote_packages).to eq(ssh_packages)
          expect(Yast::Packages.missing_remote_kind).to eq(["SSH"])
        end
      end

      context "no package is available" do
        before do
          (remote_x11_packages + ssh_packages).each do |pkg|
            allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg)
              .and_return([[pkg, :CAND, :NONE]])
          end
        end

        it "reports error for X11 and ssh packages" do
          expect(Yast::Packages.check_remote_installation_packages).to_not be_empty
          expect(Yast::Packages.missing_remote_packages.sort)
            .to eq((ssh_packages + remote_x11_packages).sort)
          expect(Yast::Packages.missing_remote_kind).to eq(["SSH", "DISPLAY_IP"])
        end
      end
    end

    context "on vnc installation" do
      let(:vnc) { true }
      let(:display_ip) { false }
      let(:braille) { false }
      let(:usessh) { false }

      context "needed packages are available" do
        before do
          vnc_packages.each do |pkg|
            allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg)
              .and_return([[pkg, :CAND, :CAND]])
          end
        end

        it "reports no error" do
          expect(Yast::Packages.check_remote_installation_packages).to be_empty
          expect(Yast::Packages.missing_remote_packages).to be_empty
          expect(Yast::Packages.missing_remote_kind).to be_empty
        end
      end

      context "needed packages are not available" do
        before do
          vnc_packages.each do |pkg|
            allow(Yast::Pkg).to receive(:PkgQueryProvides).with(pkg)
              .and_return([[pkg, :CAND, :NONE]])
          end
        end

        it "reports error" do
          expect(Yast::Packages.check_remote_installation_packages).to_not be_empty
          expect(Yast::Packages.missing_remote_packages).to eq(vnc_packages)
          expect(Yast::Packages.missing_remote_kind).to eq(["VNC"])
        end
      end
    end
  end

  describe "#Reset" do
    # Reset all package changes done by YaST then re-select only the products
    # which previously were selected. (see bsc#963036).
    it "does not select previously unselected items" do
      allow(Yast::Pkg).to receive(:PkgApplReset)

      allow(Y2Packager::Resolvable).to receive(:find)
        .with(kind: :product, status: :selected, transact_by: :app_high)
        .and_return([product("name" => "p1")])

      expect(Yast::Pkg).to receive(:ResolvableInstall).with("p1", :product)

      Yast::Packages.Reset([:product])
    end
  end

  describe "#ListSelected" do
    let(:unordered_products) do
      [
        product("name" => "p3", "status" => :selected, "source" => 15),
        product("name" => "p4", "status" => :available, "source" => 40),
        product("name" => "p1", "status" => :selected, "source" => 10)
      ]
    end

    let(:filtered_products) do
      [
        product("name" => "p3", "status" => :selected, "source" => 15),
        product("name" => "p1", "status" => :selected, "source" => 10)
      ]
    end

    let(:ordered_products) do
      [
        product("name" => "p1", "status" => :selected, "source" => 10),
        product("name" => "p3", "status" => :selected, "source" => 15)
      ]
    end

    let(:unordered_patterns) do
      [
        pattern("name" => "p3", "status" => :selected, "order" => "3", "user_visible" => true),
        pattern("name" => "p1", "status" => :selected, "order" => "1", "user_visible" => false),
        pattern("name" => "p2", "status" => :available, "order" => "2", "user_visible" => true)
      ]
    end

    let(:filtered_patterns) do
      [
        pattern("name" => "p3", "status" => :selected, "order" => "3", "user_visible" => true)
      ]
    end

    before do
      allow(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
        .and_return(unordered_products)
    end

    it "obtains a list of resolvables of the given type" do
      expect(Y2Packager::Resolvable).to receive(:find).with(kind: :product)

      subject.ListSelected(:product, "")
    end

    it "filters and sorts not selected resolvables from the list" do
      expect(subject.ListSelected(:product, "")).to eq(filtered_products.map {|t| t.name}.sort)
    end

    it "filters and sorts not user visible resolvables from the list for type pattern" do
      expect(Y2Packager::Resolvable).to receive(:find).with(kind: :pattern)
        .and_return(unordered_patterns)
      expect(subject.ListSelected(:pattern, "")).to eq(filtered_patterns.map {|t| t.name}.sort)
    end

    it "returns an empty list if no resolvables selected" do
      allow(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
        .and_return([])

      expect(subject.ListSelected(:product, "Product: %1")).to eql([])
    end

    it "returns a list with each resultant resolvable formatted as the format given" do
      expect(subject.ListSelected(:product, "Product: %1")).to eql(
        [
          "Product: p1",
          "Product: p3"
        ]
      )
    end
  end

  describe "#Summary" do
    before do
      # mock disk space calculation
      allow(subject).to receive(:CheckDiskSize).and_return(true)
      allow(Yast::SpaceCalculation).to receive(:CheckDiskFreeSpace).and_return([])
      allow(Yast::SpaceCalculation).to receive(:GetFailedMounts).and_return([])

      allow(Yast::PackagesProposal).to receive(:GetAllResolvablesForAllTypes)
        .and_return(package: ["grub2"], pattern: ["kde"])
    end

    context "YaST preselected items are deselected by user" do
      before do
        expect(Y2Packager::Resolvable).to receive(:find).with(name: "grub2", kind: :package)
          .and_return([package({"status" => :available})])
        expect(Y2Packager::Resolvable).to receive(:find).with(name: "kde", kind: :pattern)
          .and_return([package({"status" => :available, "summary" => "KDE Desktop Environment"})])
      end

      it "Reports missing pre-selected packages" do
        summary = subject.Summary([:package], false)
        expect(summary["warning"]).to include("grub2")
      end

      it "Reports missing pre-selected patterns" do
        summary = subject.Summary([:package], false)
        expect(summary["warning"]).to include("KDE Desktop Environment")
      end

      it "Installation/upgrade is blocked" do
        summary = subject.Summary([:package], false)
        expect(summary["warning_level"]).to eq(:blocker)
      end
    end

    context "YaST preselected items are not deselected by user" do
      before do
        expect(Y2Packager::Resolvable).to receive(:find).with(name: "grub2", kind: :package)
          .and_return([package({"status" => :selected})])
        expect(Y2Packager::Resolvable).to receive(:find).with(name: "kde", kind: :pattern)
          .and_return([package({"status" => :selected})])
      end

      it "Does not report missing pre-selected packages" do
        summary = subject.Summary([:package], false)
        expect(summary["warning"]).to be_nil
      end

      it "Does not report missing pre-selected patterns" do
        summary = subject.Summary([:package], false)
        expect(summary["warning"]).to be_nil
      end

      it "Installation/upgrade is not blocked" do
        summary = subject.Summary([:package], false)
        expect(summary["warning_level"]).to_not eq(:blocker)
      end
    end
  end

  describe "#SummaryHelp" do
    it "runs all code and returns a String" do
      expect(subject.SummaryHelp([:pattern, :size])).to be_a(String)
    end
  end

  describe "#proposal_for_update" do
    before do
      allow(subject).to receive(:PackagesProposalChanged).and_return(changed)
    end

    context "when packages proposal was changed" do
      let(:changed) { true }

      it "selects system packages" do
        expect(subject).to receive(:SelectSystemPackages).with(false)
        subject.proposal_for_update
      end
    end

    context "when packages proposal was not changed" do
      let(:changed) { false }

      it "does not select system packages" do
        expect(subject).to_not receive(:SelectSystemPackages)
        subject.proposal_for_update
      end
    end
  end

  describe "#Initialize_BaseInit" do
    before do
      allow(Yast::PackageCallbacks).to receive(:InitPackageCallbacks)
      allow(Yast::Language).to receive(:language).and_return("en_US")
      allow(Yast::Pkg).to receive(:SetTextLocale)
      @base_url = Yast::ArgRef.new("")
      @log_url = Yast::ArgRef.new("")
    end

    it "inits package callbacks" do
      expect(Yast::PackageCallbacks).to receive(:InitPackageCallbacks)

      subject.Initialize_BaseInit(false, @base_url, @log_url)
    end

    it "sets text locale" do
      expect(Yast::Pkg).to receive(:SetTextLocale).with("en_US")

      subject.Initialize_BaseInit(false, @base_url, @log_url)
    end

    it "fills base_url param from install.inf" do
      allow(Yast::InstURL).to receive("installInf2Url").and_return("cd:/?device=/dev/sr0")

      subject.Initialize_BaseInit(false, @base_url, @log_url)
      expect(@base_url.value).to eq "cd:/?device=/dev/sr0"
    end

    it "fills log_url param from install.inf with hidden password" do
      allow(Yast::InstURL).to receive("installInf2Url").and_return("ftp://chuck:norris@hell.com")

      subject.Initialize_BaseInit(false, @base_url, @log_url)
      expect(@log_url.value).to eq "ftp://chuck:PASSWORD@hell.com"
    end

    it "escaped backslashes in base_url (bsc#1032506)" do
      allow(Yast::InstURL).to receive("installInf2Url")
        .and_return("cd:/?device=/dev/disk/by-id/scsi-S__\\x5b")

      subject.Initialize_BaseInit(false, @base_url, @log_url)
      expect(@base_url.value).to eq "cd:/?device=/dev/disk/by-id/scsi-S__%5Cx5b"
      expect { URI.parse(@base_url.value) }.to_not raise_error
    end
  end

  describe "#adjust_repo_priority" do
    before do
      expect(Yast::Pkg).to receive(:SourceGetCurrent).with(true).and_return(repos.keys)
      repos.each do |id, data|
        expect(Yast::Pkg).to receive(:SourceGeneralData).with(id).and_return(data).at_least(:once)
      end
    end

    # define the common repository cases
    let(:volatile_repo) { { "url" => "dvd:///", "priority" => 99 } }
    let(:local_repo) { { "url" => "hd:///", "priority" => 99 } }
    let(:remote_repo) { { "url" => "http:///example.com/repo", "priority" => 99 } }

    # share the testing scenarios
    shared_examples "keeps priority" do
      it "does not change the priority" do
        expect(Yast::Pkg).to_not receive(:SourceSetPriority)
        subject.send(:adjust_repo_priority)
      end
    end

    shared_examples "sets priority" do |repo, prio|
      it "changes the priority" do
        expect(Yast::Pkg).to receive(:SourceSetPriority).with(repo, prio)
        subject.send(:adjust_repo_priority)
      end
    end

    # no priority change scenarios

    context "installing from a DVD without any addon" do
      let(:repos) { { 0 => volatile_repo } }
      it_behaves_like "keeps priority"
    end

    context "installing from a DVD with a remote addon" do
      let(:repos) { { 0 => volatile_repo, 1 => remote_repo } }
      it_behaves_like "keeps priority"
    end

    context "installing from a DVD with a USB addon" do
      let(:repos) { { 0 => volatile_repo, 1 => local_repo } }
      it_behaves_like "keeps priority"
    end

    context "installing from a DVD with an USB and a remote addon" do
      let(:repos) { { 0 => volatile_repo, 1 => local_repo, 2 => remote_repo } }
      it_behaves_like "keeps priority"
    end

    context "installing from a DVD with a DVD and a remote addon" do
      let(:repos) { { 0 => volatile_repo, 1 => volatile_repo, 2 => remote_repo } }
      it_behaves_like "keeps priority"
    end

    context "installing from a remote repo without any addon" do
      let(:repos) { { 0 => remote_repo } }
      it_behaves_like "keeps priority"
    end

    context "installing from a remote repo with a remote addon" do
      let(:repos) { { 0 => remote_repo, 1 => remote_repo } }
      it_behaves_like "keeps priority"
    end

    context "installing from a remote repo with a DVD addon" do
      let(:repos) { { 0 => remote_repo, 1 => volatile_repo } }
      it_behaves_like "keeps priority"
    end

    context "installing from a remote repo with 2 DVD addons" do
      let(:repos) { { 0 => remote_repo, 1 => volatile_repo, 2 => volatile_repo } }
      it_behaves_like "keeps priority"
    end

    # priority changed scenarios

    context "installing from a DVD with a DVD addon" do
      let(:repos) { { 0 => volatile_repo, 1 => volatile_repo } }
      it_behaves_like "sets priority", 0, 100
    end

    context "installing from a DVD with 2 DVD addons" do
      let(:repos) { { 0 => volatile_repo, 1 => volatile_repo, 2 => volatile_repo } }
      it_behaves_like "sets priority", 0, 100
    end

    context "installing from a DVD with an USB and a DVD addon" do
      let(:repos) { { 0 => volatile_repo, 1 => local_repo, 2 => volatile_repo } }
      it_behaves_like "sets priority", 0, 100
    end
  end

  # helper for the #repo_schemes tests to mock the repository configuration
  def expect_source_urls(mapping)
    expect(Yast::Pkg).to receive(:SourceGetCurrent).with(true).and_return(mapping.keys)

    mapping.each do |id, url|
      expect(Yast::Pkg).to receive(:SourceURL).with(id).and_return(url)
    end
  end

  describe "#repo_schemes" do
    it "returns empty list if no repository is defined" do
      expect_source_urls({})
      expect(subject.repo_schemes).to eq([])
    end

    it "returns all used schemes" do
      expect_source_urls(
        0 => "http://example.com",
        1 => "https://example.com",
        2 => "ftp://example.com",
        3 => "dir:///packages",
        4 => "dvd:///"
      )
      expect(subject.repo_schemes).to eq(["http", "https", "ftp", "dir", "dvd"])
    end

    it "returns unique list" do
      expect_source_urls(
        0 => "http://example.com",
        1 => "http://example2.com",
        7 => "ftp://example.com",
        8 => "ftp://example2.com"
      )
      expect(subject.repo_schemes).to eq(["http", "ftp"])
    end

    it "returns the scheme of the base URL for ISO scheme" do
      expect_source_urls(
        # ISO over NFS, see "man zypper"
        0 => "iso:/subdir?iso=DVD1.iso&url=nfs://server/dir&mnt=/nfs&filesystem=udf"
      )
      expect(subject.repo_schemes).to eq(["nfs"])
    end

    it "converts the scheme names to lower case" do
      expect_source_urls(
        0 => "HTTP://example.com",
        8 => "FTP://example2.com"
      )
      expect(subject.repo_schemes).to eq(["http", "ftp"])
    end

    it "ignores invalid URL" do
      expect_source_urls(0 => ":")
      expect(subject.repo_schemes).to eq([])
    end

    it "ignores incomplete ISO URL (missing 'url' parameter)" do
      expect_source_urls(0 => "iso:/subdir?iso=DVD1.iso&mnt=/nfs&filesystem=udf")
      expect(subject.repo_schemes).to eq([])
    end

    it "ignores incomplete ISO URL (empty 'url' parameter)" do
      expect_source_urls(0 => "iso:/subdir?iso=DVD1.iso&url=&mnt=/nfs&filesystem=udf")
      expect(subject.repo_schemes).to eq([])
    end

    it "ignores invalid ISO URL (invalid 'url' parameter)" do
      expect_source_urls(
        0 => "iso:/subdir?iso=DVD1.iso&url=:&filesystem=udf"
      )
      expect(subject.repo_schemes).to eq([])
    end
  end

  describe "#sourceAccessPackages" do
    it "returns empty list if no repository is defined" do
      expect(subject).to receive(:repo_schemes).and_return([])
      expect(subject.sourceAccessPackages).to eq([])
    end

    # these do not need any extra package to access them
    it "returns empty list for http(s), ftp, hd, cd, dvd and dir schemes" do
      schemes = ["http", "https", "ftp", "hd", "cd", "dvd", "dir"]
      expect(subject).to receive(:repo_schemes).and_return(schemes)
      expect(subject.sourceAccessPackages).to eq([])
    end

    it "returns 'nfs-client' for nfs scheme" do
      schemes = ["nfs"]
      expect(subject).to receive(:repo_schemes).and_return(schemes)
      expect(subject.sourceAccessPackages).to eq(["nfs-client"])
    end

    it "returns 'cifs-mount' for smb scheme" do
      schemes = ["smb"]
      expect(subject).to receive(:repo_schemes).and_return(schemes)
      expect(subject.sourceAccessPackages).to eq(["cifs-mount"])
    end

    it "returns 'cifs-mount' for cifs scheme" do
      schemes = ["cifs"]
      expect(subject).to receive(:repo_schemes).and_return(schemes)
      expect(subject.sourceAccessPackages).to eq(["cifs-mount"])
    end

    it "returns 'cifs-mount' and 'nfs-client' for smb and nfs schemes" do
      schemes = ["cifs", "nfs"]
      expect(subject).to receive(:repo_schemes).and_return(schemes)
      # sort the result to make it order independent
      expect(subject.sourceAccessPackages.sort).to eq(["cifs-mount", "nfs-client"])
    end
  end

  # helper for the #repo_schemes tests to mock the repository configuration
  def expect_source_urls(mapping)
    expect(Yast::Pkg).to receive(:SourceGetCurrent).with(true).and_return(mapping.keys)

    mapping.each do |id, url|
      expect(Yast::Pkg).to receive(:SourceURL).with(id).and_return(url)
    end
  end

  describe "#repo_schemes" do
    it "returns empty list if no repository is defined" do
      expect_source_urls({})
      expect(subject.repo_schemes).to eq([])
    end

    it "returns all used schemes" do
      expect_source_urls(
        0 => "http://example.com",
        1 => "https://example.com",
        2 => "ftp://example.com",
        3 => "dir:///packages",
        4 => "dvd:///"
      )
      expect(subject.repo_schemes).to eq(["http", "https", "ftp", "dir", "dvd"])
    end

    it "returns unique list" do
      expect_source_urls(
        0 => "http://example.com",
        1 => "http://example2.com",
        7 => "ftp://example.com",
        8 => "ftp://example2.com"
      )
      expect(subject.repo_schemes).to eq(["http", "ftp"])
    end

    it "returns the scheme of the base URL for ISO scheme" do
      expect_source_urls(
        # ISO over NFS, see "man zypper"
        0 => "iso:/subdir?iso=DVD1.iso&url=nfs://server/dir&mnt=/nfs&filesystem=udf"
      )
      expect(subject.repo_schemes).to eq(["nfs"])
    end

    it "converts the scheme names to lower case" do
      expect_source_urls(
        0 => "HTTP://example.com",
        8 => "FTP://example2.com"
      )
      expect(subject.repo_schemes).to eq(["http", "ftp"])
    end

    it "ignores invalid URL" do
      expect_source_urls(0 => ":")
      expect(subject.repo_schemes).to eq([])
    end

    it "ignores incomplete ISO URL (missing 'url' parameter)" do
      expect_source_urls(0 => "iso:/subdir?iso=DVD1.iso&mnt=/nfs&filesystem=udf")
      expect(subject.repo_schemes).to eq([])
    end

    it "ignores incomplete ISO URL (empty 'url' parameter)" do
      expect_source_urls(0 => "iso:/subdir?iso=DVD1.iso&url=&mnt=/nfs&filesystem=udf")
      expect(subject.repo_schemes).to eq([])
    end

    it "ignores invalid ISO URL (invalid 'url' parameter)" do
      expect_source_urls(
        0 => "iso:/subdir?iso=DVD1.iso&url=:&filesystem=udf"
      )
      expect(subject.repo_schemes).to eq([])
    end
  end

  describe "#sourceAccessPackages" do
    it "returns empty list if no repository is defined" do
      expect(subject).to receive(:repo_schemes).and_return([])
      expect(subject.sourceAccessPackages).to eq([])
    end

    # these do not need any extra package to access them
    it "returns empty list for http(s), ftp, hd, cd, dvd and dir schemes" do
      schemes = ["http", "https", "ftp", "hd", "cd", "dvd", "dir"]
      expect(subject).to receive(:repo_schemes).and_return(schemes)
      expect(subject.sourceAccessPackages).to eq([])
    end

    it "returns 'nfs-client' for nfs scheme" do
      schemes = ["nfs"]
      expect(subject).to receive(:repo_schemes).and_return(schemes)
      expect(subject.sourceAccessPackages).to eq(["nfs-client"])
    end

    it "returns 'cifs-mount' for smb scheme" do
      schemes = ["smb"]
      expect(subject).to receive(:repo_schemes).and_return(schemes)
      expect(subject.sourceAccessPackages).to eq(["cifs-mount"])
    end

    it "returns 'cifs-mount' for cifs scheme" do
      schemes = ["cifs"]
      expect(subject).to receive(:repo_schemes).and_return(schemes)
      expect(subject.sourceAccessPackages).to eq(["cifs-mount"])
    end

    it "returns 'cifs-mount' and 'nfs-client' for smb and nfs schemes" do
      schemes = ["cifs", "nfs"]
      expect(subject).to receive(:repo_schemes).and_return(schemes)
      # sort the result to make it order independent
      expect(subject.sourceAccessPackages.sort).to eq(["cifs-mount", "nfs-client"])
    end
  end

  describe "#proposal_changed?" do
    before do
      allow(Y2Packager::Resolvable).to receive(:find).with(kind: :patch)
        .and_return([])

      allow(Y2Packager::Resolvable).to receive(:find).with(kind: :pattern)
        .and_return(
          [pattern("name" => "minimal_base", "status" => :selected),
           pattern("name" => "base", "status" => :selected)]
        )
      allow(Y2Packager::Resolvable).to receive(:find).with(kind: :product)
        .and_return([product("name" => "SLES", "status" => :selected)])
      allow(Yast::Pkg).to receive(:GetAdditionalLocales).and_return([])
      allow(Yast::Pkg).to receive(:GetPackageLocale).and_return("en_US")

      subject.cached_proposal = { "packages" => ["SUSEConnect 0.3.16 5.13 x86_64",
                                                 "aaa_base 84.87+git20180409.04c9dae 3.3.2 x86_64",
                                                 "bash 4.4 9.7.1 x86_64"],
        "patterns" => ["base", "minimal_base"],
        "products" => ["SLES"], "patches" => [], "languages" => ["en_US"] }
    end

    context "current selection has not been changed" do
      it "returns false" do
        allow(Yast::Pkg).to receive(:GetPackages)
          .and_return(["aaa_base 84.87+git20180409.04c9dae 3.3.2 x86_64",
                       "bash 4.4 9.7.1 x86_64", "SUSEConnect 0.3.16 5.13 x86_64"])
        expect(Yast::Packages.send(:proposal_changed?)).to eq false
      end
    end

    context "package selection has been changed" do
      it "returns true" do
        allow(Yast::Pkg).to receive(:GetPackages)
          .and_return(["aaa_base 84.87+git20180409.04c9dae 3.3.2 x86_64",
                       "bash 4.4 9.7.1 x86_64"])
        expect(Yast::Packages.send(:proposal_changed?)).to eq true
      end
    end
  end
end
