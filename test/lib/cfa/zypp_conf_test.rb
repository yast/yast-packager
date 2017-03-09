#!/usr/bin/env rspec

require_relative "../../test_helper"

require "packager/cfa/zypp_conf"
require "tmpdir"

describe Yast::Packager::CFA::ZyppConf do
  ZYPP_CONF_EXAMPLE = FIXTURES_PATH.join("zypp/zypp.conf").freeze
  ZYPP_CONF_EXPECTED = FIXTURES_PATH.join("zypp/zypp.conf.expected").freeze

  subject(:config) { Yast::Packager::CFA::ZyppConf.new }
  let(:zypp_conf_path) { ZYPP_CONF_EXAMPLE }

  before do
    stub_const("Yast::Packager::CFA::ZyppConf::PATH", zypp_conf_path)
  end

  describe "#set_minimalistic!" do
    before { config.load }

    it "sets minimalistic options" do
      config.set_minimalistic!
      main = config.section("main")
      expect(main["solver.onlyRequires"]).to eq("true")
      expect(main["rpm.install.excludedocs"]).to eq("yes")
      expect(main["multiversion"]).to be_nil
    end
  end

  describe "#save" do
    let(:tmpdir) { Dir.mktmpdir }
    let(:zypp_conf_path) { File.join(tmpdir, "zypp.conf") }
    let(:expected_content) { File.read(FIXTURES_PATH.join("zypp/zypp.conf.expected")) }

    before do
      FileUtils.cp(ZYPP_CONF_EXAMPLE, File.join(tmpdir, "zypp.conf"))
      config.load
    end

    after do
      FileUtils.remove_entry tmpdir
    end

    it "do nothing if no option is not modified" do
      config.save
      expect(File.read(zypp_conf_path)).to eq(File.read(ZYPP_CONF_EXAMPLE))
    end

    it "modifies the file accordingly to given options" do
      # FIXME: now expected file include also whitespace changes caused
      # by https://github.com/hercules-team/augeas/issues/450
      # modify it when augeas is fixed
      config.set_minimalistic!
      config.save
      expect(File.read(zypp_conf_path)).to eq(File.read(ZYPP_CONF_EXPECTED))
    end
  end
end
