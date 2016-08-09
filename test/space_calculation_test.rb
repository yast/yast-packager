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
SCR_BASH_OUTPUT_PATH = Yast::Path.new(".target.bash_output")

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
        allow(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH, /^mkdir -p/)
        allow(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH, /^umount/)
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

# storage-ng
=begin
  describe "#size_from_string" do
    it "converts string without units bytes" do
      expect(Yast::SpaceCalculation.size_from_string("42.00")).to eq(42)
    end

    it "converts B unit to bytes" do
      expect(Yast::SpaceCalculation.size_from_string("42B")).to eq(42)
    end

    it "accepts KiB size parameter" do
      expect(Yast::SpaceCalculation.size_from_string("42KiB")).to eq(42 * (2**10))
    end

    it "accepts MiB size parameter" do
      expect(Yast::SpaceCalculation.size_from_string("42MiB")).to eq(42 * (2**20))
    end

    it "accepts GiB size parameter" do
      expect(Yast::SpaceCalculation.size_from_string("42GiB")).to eq(42 * (2**30))
    end

    it "accepts TiB size parameter" do
      expect(Yast::SpaceCalculation.size_from_string("42TiB")).to eq(42 * (2**40))
    end

    it "accepts PiB size parameter" do
      expect(Yast::SpaceCalculation.size_from_string("42PiB")).to eq(42 * (2**50))
    end

    it "ignores space separators" do
      expect(Yast::SpaceCalculation.size_from_string("42 KiB")).to eq(42 * 1024)
    end

    it "accepts floats" do
      expect(Yast::SpaceCalculation.size_from_string("42.42 KiB")).to eq((42.42 * 1024).to_i)
    end

    it "converts '0.00' to zero" do
      expect(Yast::SpaceCalculation.size_from_string("0.00")).to eq(0)
    end
  end
=end

  describe "#btrfs_snapshots?" do
    let(:dir) { "/mnt" }

    it "returns true when a snapshot is found" do
      stdout = "ID 256 gen 5 cgen 5 top level 5 otime 2014-09-19 10:27:05 path snapshot\n"
      expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_OUTPUT_PATH,
        "btrfs subvolume list -s #{dir}").and_return("stdout" => stdout, "exit" => 0)
      expect(Yast::SpaceCalculation.btrfs_snapshots?(dir)).to be true
    end

    it "returns false when a snapshot is not found" do
      expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_OUTPUT_PATH,
        "btrfs subvolume list -s #{dir}").and_return("stdout" => "", "exit" => 0)
      expect(Yast::SpaceCalculation.btrfs_snapshots?(dir)).to be false
    end

    it "raises exception when btrfs tool fails" do
      expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_OUTPUT_PATH,
        "btrfs subvolume list -s #{dir}").and_return("stdout" => "", "exit" => 127)
      expect { Yast::SpaceCalculation.btrfs_snapshots?(dir) }.to raise_error(
        /Cannot detect Btrfs snapshots, subvolume listing failed/)
    end
  end

# storage-ng
=begin
  describe "#btrfs_used_size" do
    let(:dir) { "/mnt" }

    it "returns sum of used sizes reported by btrfs tool" do
      stdout = <<EOF
Data: total=1.33GiB, used=876.35MiB
System, DUP: total=8.00MiB, used=4.00KiB
System: total=4.00MiB, used=0.00B
Metadata, DUP: total=339.00MiB, used=77.03MiB
Metadata: total=8.00MiB, used=0.00B
EOF
      expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_OUTPUT_PATH,
        "LC_ALL=C btrfs filesystem df #{dir}").and_return("stdout" => stdout, "exit" => 0)
      expect(Yast::SpaceCalculation.btrfs_used_size(dir)).to eq(999_695_482)
    end

    it "raises an exception when btrfs tool fails" do
      expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_OUTPUT_PATH,
        "LC_ALL=C btrfs filesystem df #{dir}").and_return("stdout" => "", "exit" => 127)
      expect { Yast::SpaceCalculation.btrfs_used_size(dir) }.to raise_error(
        /Cannot detect Btrfs disk usage/)
    end

    it "ignores lines without 'used' value" do
      # the same as in the test above, but removed "used=0.00B" values
      stdout = <<EOF
Data: total=1.33GiB, used=876.35MiB
System, DUP: total=8.00MiB, used=4.00KiB
System: total=4.00MiB
Metadata, DUP: total=339.00MiB, used=77.03MiB
Metadata: total=8.00MiB
EOF
      expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_OUTPUT_PATH,
        "LC_ALL=C btrfs filesystem df #{dir}").and_return("stdout" => stdout, "exit" => 0)
      expect(Yast::SpaceCalculation.btrfs_used_size(dir)).to eq(999_695_482)
    end
  end
=end

  describe "#EvaluateFreeSpace" do
    let(:run_df) { YAML.load_file(File.join(DATA_PATH, "run_df.yml")) }
    let(:destdir) { "/mnt" }

    before do
      expect(Yast::Installation).to receive(:destdir).and_return(destdir)
      allow(Yast::Installation).to receive(:dirinstall_installing_into_dir)
    end

    it "Reads current disk usage and reserves extra free space" do
      expect(Yast::SCR).to receive(:Read).with(Yast::Path.new(".run.df")).
        and_return(run_df)

      result = [{"name" => "/", "filesystem" => "ext4", "used" => 3259080,
          "growonly" => false, "free" => 2530736}]

      expect(Yast::Pkg).to receive(:TargetInitDU).with(result)
      expect(Yast::SpaceCalculation.EvaluateFreeSpace(15)).to eq(result)
    end

    it "sets 'growonly' flag when btrfs with a snapshot is found" do
      run_df_btrfs = run_df
      run_df_btrfs.last["type"] = "btrfs"

      expect(Yast::SCR).to receive(:Read).with(Yast::Path.new(".run.df")).
        and_return(run_df_btrfs)
      expect(Yast::SpaceCalculation).to receive(:btrfs_used_size).with(destdir).
        and_return(3259080*1024)
      expect(Yast::SpaceCalculation).to receive(:btrfs_snapshots?).with(destdir).
        and_return(true)

      result = [{"name" => "/", "filesystem" => "btrfs", "used" => 3259080,
          "growonly" => true, "free" => 2939606}]

      expect(Yast::Pkg).to receive(:TargetInitDU).with(result)
      expect(Yast::SpaceCalculation.EvaluateFreeSpace(15)).to eq(result)
    end

  end
end
