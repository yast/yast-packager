#!/usr/bin/env rspec

require_relative "../../test_helper"
require "packager/cfa/zypp_conf"

describe Yast::Packager::CFA::ZyppConf do
  subject(:config) { Yast::Packager::CFA::ZyppConf.new }

  before do
    stub_const("Yast::Packager::CFA::ZyppConf::PATH", FIXTURES_PATH.join("zypp/zypp.conf"))
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
end
