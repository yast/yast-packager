#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "Mtab"
Yast.import "WFM"
Yast.import "SCR"

MTABNAME = "/etc/mtab".freeze
DESTDIR = "/mnt".freeze

describe Yast::Mtab do
  subject(:mtab) { Yast::Mtab }

  describe "#clone_to_target" do
    let(:org_mtab) { File.binread(File.join(DATA_PATH, "org_mtab")) }
    let(:patched_mtab) { File.binread(File.join(DATA_PATH, "patched_mtab")) }

    before do
      expect(Yast::WFM).to receive(:Read)
        .with(Yast::Path.new(".local.string"), MTABNAME)
        .and_return(org_mtab)
      expect(Yast::SCR).to receive(:Write)
        .with(Yast::Path.new(".target.string"), File.join(DESTDIR, MTABNAME), patched_mtab)
      allow(File).to receive(:directory?).and_return(true)
      allow(Yast::Installation).to receive(:destdir).and_return(DESTDIR)
    end

    it "writes /etc/mtab to target system" do
      mtab.clone_to_target
    end
  end
end
