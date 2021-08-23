#!/usr/bin/env rspec

require_relative "../../test_helper"

require "packager/cfa/dnf_conf"
require "tmpdir"

describe Yast::Packager::CFA::DnfConf do
  DNF_CONF_EXAMPLE = DATA_PATH.join("dnf/dnf.conf").freeze
  DNF_CONF_EXPECTED = DATA_PATH.join("dnf/dnf.conf.expected").freeze

  subject(:config) { Yast::Packager::CFA::DnfConf.new }
  let(:dnf_conf_path) { DNF_CONF_EXAMPLE }

  before do
    stub_const("Yast::Packager::CFA::DnfConf::PATH", dnf_conf_path)
  end

  describe "#set_minimalistic!" do
    before { config.load }

    it "sets minimalistic options" do
      config.set_minimalistic!
      main = config.section("main")
      expect(main["install_weak_deps"]).to eq("False")
      expect(main["tsflags"]).to eq("nodocs")
    end
  end

  describe "#save" do
    let(:tmpdir) { Dir.mktmpdir }
    let(:dnf_conf_path) { File.join(tmpdir, "dnf.conf") }
    let(:expected_content) { File.read(DATA_PATH.join("dnf/dnf.conf.expected")) }

    before do
      FileUtils.cp(DNF_CONF_EXAMPLE, File.join(tmpdir, "dnf.conf"))
      config.load
    end

    after do
      FileUtils.remove_entry tmpdir
    end

    it "do nothing if no option is not modified" do
      config.save
      expect(File.read(dnf_conf_path)).to eq(File.read(DNF_CONF_EXAMPLE))
    end

    it "modifies the file accordingly to given options" do
      # FIXME: now expected file include also whitespace changes caused
      # by https://github.com/hercules-team/augeas/issues/450
      # modify it when augeas is fixed
      config.set_minimalistic!
      config.save
      expect(File.read(dnf_conf_path)).to eq(File.read(DNF_CONF_EXPECTED))
    end
  end
end
