#! /usr/bin/env rspec

require_relative "./test_helper"
require 'yaml'
require 'y2storage'

Yast.import 'Stage'
Yast.import 'Mode'
Yast.import 'SCR'
Yast.import 'SpaceCalculation'

DATA_PATH = File.join(File.expand_path(File.dirname(__FILE__)), "data")
SCR_TMPDIR_PATH = Yast::Path.new(".target.tmpdir")
SCR_BASH_PATH = Yast::Path.new(".target.bash")
SCR_BASH_OUTPUT_PATH = Yast::Path.new(".target.bash_output")

def stub_devicegraph(name)
  path = File.join(DATA_PATH, "#{name}_devicegraph.yml")
  storage = Y2Storage::StorageManager.fake_from_yaml(path)
  storage.probed.copy(storage.staging)
end

def expect_to_execute(command)
  expect(Yast::SCR).to receive(:Execute).with(SCR_BASH_PATH, command)
end

def filesystem(size_k: 0, block_size: 4096, type: :ext2, tune_options: "")
  disk_size = Y2Storage::DiskSize.KiB(size_k)
  region = Y2Storage::Region.create(0, disk_size.to_i, Y2Storage::DiskSize.B(block_size))
  fs_type = Y2Storage::Filesystems::Type.new(type)
  dev_sda1 = double("Y2Storage::BlkDevice", name: "/dev/sda1", region: region, size: disk_size)
  double(
    "Y2Storage::Filesystems::BlkFilesystem",
    blk_devices: [dev_sda1],
    type: fs_type,
    tune_options: tune_options
  )
end

describe Yast::SpaceCalculation do
  describe "#get_partition_info" do

    context "on test mount during installation" do
      before do
        allow(Yast::Stage).to receive(:stage).and_return "initial"
        allow(Yast::Mode).to receive(:mode).and_return "normal"

        stub_devicegraph(target_map)
        if !with_options
          allow_any_instance_of(Storage::BlkFilesystem).to receive(:fstab_options).and_return([])
        end

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
        before(:all) do
          skip "TODO: NFS not fully supported in libstorage-ng yet"
        end

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
        before(:all) do
          skip "TODO: Encryption not fully supported in libstorage-ng yet"
        end

        let(:target_map) { "luks" }
        let(:with_options) { false }

        it "mounts the DM device" do
          expect_to_execute(/mount -o ro \/dev\/mapper\/cr_ata-VBOX_HARDDISK_VB57271fd6-27adef38-part3/).and_return(-1)
          Yast::SpaceCalculation.get_partition_info
        end
      end
    end
  end

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

    it "does not modify the argument" do
      str = "1"
      Yast::SpaceCalculation.size_from_string(str)
      expect(str).to eq "1"
    end
  end

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

  describe ".ExtJournalSize" do
    it "returns zero for ext2" do
      data = filesystem(size_k: 5 << 20, type: :ext2)
      expect(Yast::SpaceCalculation.ExtJournalSize(data)).to eq 0
    end

    it "returns zero for small ext3/4 partitions" do
      data = filesystem(size_k: 2 << 10, type: :ext3)
      expect(Yast::SpaceCalculation.ExtJournalSize(data)).to eq 0
    end

    it "returns zero if partition have no_journal option" do
      data = filesystem(size_k: 2 << 20, type: :ext4)
      expect(Yast::SpaceCalculation.ExtJournalSize(data)).to eq(0)
    end

    it "returns correct journal size in bytes for ext3/4 partitions" do
      data = filesystem(size_k: 5 << 20, type: :ext3, tune_options: "has_journal")
      expect(Yast::SpaceCalculation.ExtJournalSize(data)).to eq(128 << 20) # returns in bytes, but input in kb

      data = filesystem(size_k: 5 << 20, type: :ext4, tune_options: "has_journal")
      expect(Yast::SpaceCalculation.ExtJournalSize(data)).to eq(128 << 20)

      data = filesystem(size_k: 2 << 20, type: :ext4, tune_options: "has_journal")
      expect(Yast::SpaceCalculation.ExtJournalSize(data)).to eq(64 << 20)

      # use 1k blocks
      data = filesystem(size_k: 2 << 20, type: :ext4, tune_options: "has_journal", block_size: 1024)
      expect(Yast::SpaceCalculation.ExtJournalSize(data)).to eq(32 << 20)
    end
  end

  describe ".ReiserJournalSize" do
    it "returns 32MB + 4kB regardless fs size" do
      data = filesystem(size_k: 5 << 20, type: :reiserfs)
      expect(Yast::SpaceCalculation.ReiserJournalSize(data)).to eq((32 << 20) + (4 << 10))
    end
  end

  describe ".XfsJournalSize" do
    it "returns correct journal size depending on fs size" do
      data = filesystem(size_k: 2 << 10, type: :xfs)
      expect(Yast::SpaceCalculation.XfsJournalSize(data)).to eq( 10 << 20)

      data = filesystem(size_k: 50 << 20, type: :xfs)
      expect(Yast::SpaceCalculation.XfsJournalSize(data)).to eq( 25 << 20)

      data = filesystem(size_k: 50 << 30, type: :xfs)
      expect(Yast::SpaceCalculation.XfsJournalSize(data)).to eq( 2 << 30)
    end
  end

  describe ".JfsJournalSize" do
    it "returns correct journal size depending on fs size" do
      data = filesystem(size_k: 5 << 20, type: :jfs)
      expect(Yast::SpaceCalculation.JfsJournalSize(data)).to eq( 20 << 20)

      # test rounding if few more kB appears
      data = filesystem(size_k: (5 << 20) + 5, type: :jfs)
      expect(Yast::SpaceCalculation.JfsJournalSize(data)).to eq( 21 << 20)

      # test too big limitation to 128MB
      data = filesystem(size_k: 5 << 40, type: :jfs)
      expect(Yast::SpaceCalculation.JfsJournalSize(data)).to eq( 128 << 20)
    end
  end

  describe ".ReservedSpace" do
    it "count reserved space for given partition" do
      skip "TODO: mkfs_options is not properly managed yet"

      data = {
        "size_k" => 1000 << 20, "used_fs" => :jfs, "name" => "sda1",
        "fs_options" => { "opt_reserved_blocks" => { "option_value" => "0.0" } }
      }
      expect(Yast::SpaceCalculation.ReservedSpace(data)).to eq(0)

      data = {
        "size_k" => 1000 << 20, "used_fs" => :jfs, "name" => "sda1",
        "fs_options" => { "opt_reserved_blocks" => { "option_value" => "5.0" } }
      }
      expect(Yast::SpaceCalculation.ReservedSpace(data)).to eq(50 << 30)

      data = {
        "size_k" => 1000 << 20, "used_fs" => :jfs, "name" => "sda1",
        "fs_options" => { "opt_reserved_blocks" => { "option_value" => "12.5" } }
      }
      expect(Yast::SpaceCalculation.ReservedSpace(data)).to eq(125 << 30)
    end
  end

  describe ".EstimateFsOverhead" do
    it "returns number for FS overhead" do
      ext2_data = filesystem(size_k: 5 << 20, type: :ext2)
      expect(Yast::SpaceCalculation.EstimateFsOverhead(ext2_data)).to eq 85899345 # sorry, no clue why this number from old testsuite

      ext3_data = filesystem(size_k: 5 << 20, type: :ext3)
      expect(Yast::SpaceCalculation.EstimateFsOverhead(ext3_data)).to eq 85899345 # sorry, no clue why this number from old testsuite

      ext4_data = filesystem(size_k: 5 << 20, type: :ext4)
      expect(Yast::SpaceCalculation.EstimateFsOverhead(ext4_data)).to eq 85899345 # sorry, no clue why this number from old testsuite

      xfs_data = filesystem(size_k: 5 << 20, type: :xfs)
      expect(Yast::SpaceCalculation.EstimateFsOverhead(xfs_data)).to eq 5368709 # sorry, no clue why this number from old testsuite

      jfs_data = filesystem(size_k: 5 << 20, type: :jfs)
      expect(Yast::SpaceCalculation.EstimateFsOverhead(jfs_data)).to eq 16106127 # sorry, no clue why this number from old testsuite

      reiser_data = filesystem(size_k: 5 << 20, type: :reiserfs)
      expect(Yast::SpaceCalculation.EstimateFsOverhead(reiser_data)).to eq 0 # sorry, no clue why this number from old testsuite

      btrfs_data = filesystem(size_k: 5 << 20, type: :btrfs)
      expect(Yast::SpaceCalculation.EstimateFsOverhead(btrfs_data)).to eq 0 # sorry, no clue why this number from old testsuite
    end
  end

  describe ".EstimateTargetUsage" do
    it "returns empty array for nil" do
      expect(Yast::SpaceCalculation.EstimateTargetUsage(nil)).to eq []
    end

    it "returns empty array for empty array input" do
      expect(Yast::SpaceCalculation.EstimateTargetUsage([])).to eq []
    end

    it "returns new array with updated empty and used space" do
      data = [{ "name" => "/", "used" => 0, "free" => 10000000 }]
      expected_data = [{"free" => 9879168, "name" => "/", "used" => 120832}] # data from old testsuite
      expect(Yast::SpaceCalculation.EstimateTargetUsage(data)).to eq expected_data

      # separated home, nothing to install there
      data = [
        { "name" => "/", "used" => 0, "free" => 10000000 },
        { "name" => "/home", "used" => 0, "free" => 1000000 }
      ]
      expected_data = [
        {"free" =>9879168, "name"=>"/", "used"=>120832},
        {"free"=>1000000, "name"=>"/home", "used"=>0}
      ]
      expect(Yast::SpaceCalculation.EstimateTargetUsage(data)).to eq expected_data

      # multiple partitions
      data = [
            { "name" => "/", "used" => 0, "free" => 10000000 },
            { "name" => "/boot", "used" => 0, "free" => 1000000 },
            { "name" => "/usr", "used" => 0, "free" => 1000000 }
          ]
      expected_data = [
        {"free" => 9891456, "name" => "/", "used" => 108544},
        {"free" => 988736, "name" => "/boot", "used" => 11264},
        {"free" => 998976, "name" => "/usr", "used" => 1024}
      ]
      expect(Yast::SpaceCalculation.EstimateTargetUsage(data)).to eq expected_data
    end
  end
end
