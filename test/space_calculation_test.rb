#! /usr/bin/env rspec

require_relative "./test_helper"
require 'yaml'

Yast.import 'WFM'
Yast.import 'Stage'
Yast.import 'Mode'
Yast.import 'SCR'
Yast.import 'SpaceCalculation'

DATA_PATH = File.join(File.expand_path(File.dirname(__FILE__)), "data")
SCR_TMPDIR_PATH = Yast::Path.new(".target.tmpdir")
SCR_BASH_PATH = Yast::Path.new(".target.bash")

def stub_target_map(name, with_fstopt)
  path = File.join(DATA_PATH, "#{name}_target_map.yml")
  tm = YAML.load_file(path)
  # Remove the "fstopt" key from every partition
  if with_fstopt == false
    tm.each do |k,v|
      v["partitions"].each {|p| p.delete("fstopt") }
    end
  end
  allow(Yast::WFM).to(receive(:call).with("wrapper_storage",
                                          ["GetTargetMap"]).and_return(tm))
end

def expect_to_execute(command)
  expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH, command)
end

describe Yast::SpaceCalculation do
  describe "#get_partition_info" do

    context "on test mount during installation" do
      before do
        allow(Yast::Stage).to receive(:stage).and_return "initial"
        allow(Yast::Mode).to receive(:mode).and_return "normal"

        stub_target_map(target_map, with_options)

        allow(Yast::SCR).to receive(:Read).with(SCR_TMPDIR_PATH).and_return "/tmp"
        allow(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH, /^test -d.* mkdir -p/)
        allow(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH, /^\/bin\/umount/)
      end

      context "on xfs" do
        let(:target_map) { "xfs" }

        context "with mount options" do
          let(:with_options) { true }

          it "honours the options and adds 'ro'" do
            expect_to_execute(/mount -o acl,user_xattr,ro \/dev\/vda3/).and_return(-1)
            Yast::SpaceCalculation.get_partition_info
          end
        end

        context "without mount options" do
          let(:with_options) { false }

          it "uses 'ro'" do
            expect_to_execute(/mount -o ro \/dev\/vda3/).and_return(-1)
            Yast::SpaceCalculation.get_partition_info
          end
        end
      end

      context "on nfs" do
        let(:target_map) { "nfs" }

        context "with mount options" do
          let(:with_options) { true }

          it "honours the options and adds 'ro' and 'nolock'" do
            expect_to_execute(/mount -o noatime,nfsvers=3,nolock,ro nfs-host:\/nfsroot/).and_return(-1)
            Yast::SpaceCalculation.get_partition_info
          end
        end

        context "without mount options" do
          let(:with_options) { false }

          it "uses 'ro,nolock'" do
            expect_to_execute(/mount -o ro,nolock nfs-host:\/nfsroot/).and_return(-1)
            Yast::SpaceCalculation.get_partition_info
          end
        end
      end

      context "on non encrypted device" do
        let(:target_map) { "xfs" }
        let(:with_options) { false }

        it "mounts the plain device" do
          expect_to_execute(/mount -o ro \/dev\/vda3/).and_return(-1)
          Yast::SpaceCalculation.get_partition_info
        end
      end

      context "on encrypted device" do
        let(:target_map) { "luks" }
        let(:with_options) { false }

        it "mounts the DM device" do
          expect_to_execute(/mount -o ro \/dev\/mapper\/cr_ata-VBOX_HARDDISK_VB57271fd6-27adef38-part3/).and_return(-1)
          Yast::SpaceCalculation.get_partition_info
        end
      end
    end
  end
end
