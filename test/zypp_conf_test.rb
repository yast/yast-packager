#!/usr/bin/env rspec

require_relative "test_helper"

SCR_BASH_PATH = Yast::Path.new(".target.bash")
ZYPP_CONF = "/etc/zypp/zypp.conf"
SED_CALL = "/usr/bin/sed -i \'s/"

Yast.import "ZyppConf"

describe Yast::ZyppConf do
  subject(:zypp_conf)  { Yast::ZyppConf }
    
  describe "#set_minimalistic" do

    before do
      expect(Yast::Report).not_to receive(:Error)
      allow(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH,
        SED_CALL + "# set by YAST//g\' " + ZYPP_CONF)
    end

    context "when set to true" do
      it "returns no error" do
        expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH,
          SED_CALL +
          ".*onlyRequires.*/\\n# set by YAST\\nsolver.onlyRequires = true/g\' " + 
          ZYPP_CONF).and_return(0)
        expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH,
          SED_CALL +
          ".*rpm.install.excludedocs.*/\\n# set by YAST\\nrpm.install.excludedocs = yes/g\' " + 
          ZYPP_CONF).and_return(0)
        expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH,
          SED_CALL +
          "^multiversion =.*/\\n# set by YAST\\nmultiversion =/g\' " + 
          ZYPP_CONF).and_return(0)
        zypp_conf.set_minimalistic(true)
      end
    end
    context "when set to false" do
      it "returns no error" do
        expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH,
          SED_CALL +
          ".*onlyRequires.*/\\n# set by YAST\\nsolver.onlyRequires = false/g\' " + 
          ZYPP_CONF).and_return(0)
        expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH,
          SED_CALL +
          ".*rpm.install.excludedocs.*/\\n# set by YAST\\nrpm.install.excludedocs = no/g\' " + 
          ZYPP_CONF).and_return(0)
        expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH,
          SED_CALL +
          "^multiversion =.*/\\n# set by YAST\\nmultiversion = provides:multiversion(kernel)/g\' " + 
          ZYPP_CONF).and_return(0)
        zypp_conf.set_minimalistic(false)
      end
    end
  end
end
