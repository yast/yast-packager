# encoding: utf-8

# Testsuite for SpaceCalculation.ycp module
#
module Yast
  class SpaceCalculationClient < Client
    def main
      Yast.include self, "testsuite.rb"
      @READ = { "target" => { "tmpdir" => "/tmp" } }
      TESTSUITE_INIT([@READ], nil)

      Yast.import "SpaceCalculation"

      # size units - multiplies of kB blocks
      @mb = 1 << 10
      @gb = 1 << 20
      @tb = 1 << 30

      @part = {
        # 5GB
        "size_k"  => Ops.multiply(5, @gb),
        "used_fs" => :ext2,
        "name"    => "sda1"
      }

      DUMP(" ----- Journal size tests ----- ")
      DUMP("Ext2/3/4 journal size tests")

      # ext2 => no journal => 0
      TEST(lambda { SpaceCalculation.ExtJournalSize(@part) }, [], nil)

      # 128MB
      Ops.set(@part, "used_fs", :ext3)
      TEST(lambda { SpaceCalculation.ExtJournalSize(@part) }, [], nil)

      # 128MB
      Ops.set(@part, "used_fs", :ext4)
      TEST(lambda { SpaceCalculation.ExtJournalSize(@part) }, [], nil)

      # 2 MB is too small => 0
      Ops.set(@part, "size_k", Ops.multiply(2, @mb))
      TEST(lambda { SpaceCalculation.ExtJournalSize(@part) }, [], nil)

      # 2GB => 64MB
      Ops.set(@part, "size_k", Ops.multiply(2, @gb))
      TEST(lambda { SpaceCalculation.ExtJournalSize(@part) }, [], nil)

      # 2GB but 1k blocks => 32MB
      Ops.set(
        @part,
        "fs_options",
        { "opt_blocksize" => { "option_value" => "1024" } }
      )
      TEST(lambda { SpaceCalculation.ExtJournalSize(@part) }, [], nil)

      # no journal option => 0
      Ops.set(
        @part,
        "fs_options",
        { "no_journal" => { "option_value" => true } }
      )
      TEST(lambda { SpaceCalculation.ExtJournalSize(@part) }, [], nil)


      DUMP("ReiserFS journal size tests")

      Ops.set(@part, "fs_options", {})
      Ops.set(@part, "used_fs", :reiser)

      # the default is 32MB + 4kB regardeless fs size
      TEST(lambda { SpaceCalculation.ReiserJournalSize(@part) }, [], nil)


      DUMP("XFS journal size tests")

      Ops.set(@part, "used_fs", :xfs)

      # too small => 10 MB min size
      TEST(lambda { SpaceCalculation.XfsJournalSize(@part) }, [], nil)

      # medium size => 26MB
      Ops.set(@part, "size_k", Ops.multiply(50, @gb))
      TEST(lambda { SpaceCalculation.XfsJournalSize(@part) }, [], nil)

      # too large => 2GB max size
      Ops.set(@part, "size_k", Ops.multiply(5, @tb))
      TEST(lambda { SpaceCalculation.XfsJournalSize(@part) }, [], nil)



      DUMP("JFS journal size tests")

      Ops.set(@part, "used_fs", :jfs)

      # medium size
      Ops.set(@part, "size_k", Ops.multiply(5, @gb))
      TEST(lambda { SpaceCalculation.JfsJournalSize(@part) }, [], nil)

      # medium size, add few kB more so it's rounded one MB up
      Ops.set(@part, "size_k", Ops.add(Ops.multiply(5, @gb), 5))
      TEST(lambda { SpaceCalculation.JfsJournalSize(@part) }, [], nil)

      # too large => 128MB max size
      Ops.set(@part, "size_k", Ops.multiply(50, @gb))
      TEST(lambda { SpaceCalculation.JfsJournalSize(@part) }, [], nil)

      # user defined size (in MB)
      Ops.set(
        @part,
        "fs_options",
        { "opt_log_size" => { "option_value" => "10" } }
      )
      TEST(lambda { SpaceCalculation.JfsJournalSize(@part) }, [], nil)
      Ops.set(@part, "fs_options", {})

      DUMP(" ----- Extfs reserved space tests ----- ")

      # no reserved space
      TEST(lambda { SpaceCalculation.ReservedSpace(@part) }, [], nil)

      # 0%
      Ops.set(
        @part,
        "fs_options",
        { "opt_reserved_blocks" => { "option_value" => "0.0" } }
      )
      TEST(lambda { SpaceCalculation.ReservedSpace(@part) }, [], nil)

      # 5% of 50GB => 2.5GB
      Ops.set(
        @part,
        "fs_options",
        { "opt_reserved_blocks" => { "option_value" => "5.0" } }
      )
      TEST(lambda { SpaceCalculation.ReservedSpace(@part) }, [], nil)

      # 12.50% of 50GB => 6.25GB
      Ops.set(
        @part,
        "fs_options",
        { "opt_reserved_blocks" => { "option_value" => "12.50" } }
      )
      TEST(lambda { SpaceCalculation.ReservedSpace(@part) }, [], nil)

      DUMP(" ----- Fs overhead tests ----- ")

      # 5GB partition
      Ops.set(@part, "size_k", Ops.multiply(5, @gb))

      # ext2
      Ops.set(@part, "used_fs", :ext2)
      TEST(lambda { SpaceCalculation.EstimateFsOverhead(@part) }, [], nil)

      # ext3
      Ops.set(@part, "used_fs", :ext3)
      TEST(lambda { SpaceCalculation.EstimateFsOverhead(@part) }, [], nil)

      # ext4
      Ops.set(@part, "used_fs", :ext4)
      TEST(lambda { SpaceCalculation.EstimateFsOverhead(@part) }, [], nil)

      # xfs
      Ops.set(@part, "used_fs", :xfs)
      TEST(lambda { SpaceCalculation.EstimateFsOverhead(@part) }, [], nil)

      # jfs
      Ops.set(@part, "used_fs", :jfs)
      TEST(lambda { SpaceCalculation.EstimateFsOverhead(@part) }, [], nil)

      # reiser
      Ops.set(@part, "used_fs", :reiser)
      TEST(lambda { SpaceCalculation.EstimateFsOverhead(@part) }, [], nil)

      # btrfs
      Ops.set(@part, "used_fs", :btrfs)
      TEST(lambda { SpaceCalculation.EstimateFsOverhead(@part) }, [], nil)



      DUMP(" ----- Target usage tests ----- ")

      # test invalid input
      TEST(lambda { SpaceCalculation.EstimateTargetUsage(nil) }, [], nil)
      TEST(lambda { SpaceCalculation.EstimateTargetUsage([]) }, [], nil)

      # single partition
      TEST(lambda do
        SpaceCalculation.EstimateTargetUsage(
          [{ "name" => "/", "used" => 0, "free" => 10000000 }]
        )
      end, [], nil)

      # multiple partitions, separate /home (nothing to install)
      TEST(lambda do
        SpaceCalculation.EstimateTargetUsage(
          [
            { "name" => "/", "used" => 0, "free" => 10000000 },
            { "name" => "/home", "used" => 0, "free" => 1000000 }
          ]
        )
      end, [], nil)

      # multiple partitions
      TEST(lambda do
        SpaceCalculation.EstimateTargetUsage(
          [
            { "name" => "/", "used" => 0, "free" => 10000000 },
            { "name" => "/boot", "used" => 0, "free" => 1000000 },
            { "name" => "/usr", "used" => 0, "free" => 1000000 }
          ]
        )
      end, [], nil)

      nil
    end
  end
end

Yast::SpaceCalculationClient.new.main
