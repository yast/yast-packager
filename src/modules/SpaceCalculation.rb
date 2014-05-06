# encoding: utf-8

# Module:		SpaceCalculation.ycp
#
# Authors:		Klaus Kaempf (kkaempf@suse.de)
#			Gabriele Strattner (gs@suse.de)
#			Stefan Schubert (schubi@suse.de)
#
# Purpose:		Package installation functions usable
#			when the installation media is available
#			on Installation::sourcedir
#
#
# $Id$
require "yast"

module Yast
  class SpaceCalculationClass < Module

    include Yast::Logger

    def main
      Yast.import "Pkg"

      textdomain "packager"

      Yast.import "Installation"
      Yast.import "Mode"
      Yast.import "ProductFeatures"
      Yast.import "Report"
      Yast.import "String"
      Yast.import "Stage"

      @info_called = false # list partition_info already initialized?
      @partition_info = [] # information about available partitions

      @failed_mounts = []
    end

    # Return partition info list
    # @return list of available partitions
    def GetPartitionList
      deep_copy(@partition_info)
    end

    def GetFailedMounts
      deep_copy(@failed_mounts)
    end

    # Get mountpoint for a directory
    # @param [String] target directory
    # @param [Array<Hash{String => String>}] partition partitions list
    # @return mountpoint
    def GetDirMountPoint(target, partition)
      partition = deep_copy(partition)
      d = Builtins.splitstring(target, "/")
      d = Builtins.filter(d) { |fd| fd != "" }
      mountpoint = ""

      Builtins.foreach(partition) do |part|
        #  dirinstall: /test/xen dir: /test
        #  dirinstall:/var/tmp/xen dir: /
        dir = Ops.get_string(part, "name", "")
        tmpdir = ""
        Builtins.foreach(d) do |dd|
          tmpdir = Builtins.sformat("%1/%2", tmpdir, dd)
          Builtins.y2debug("tmpdir: %1 dir: %2", tmpdir, dir)
          mountpoint = dir if dir == tmpdir
        end
      end

      mountpoint = "/" if mountpoint == ""

      mountpoint
    end

    # Evaluate the free space on the file system. Runs the command "df" and creates a map
    # containig information about used and free space on every partition.
    # Free space is calculated respecting the spare_percentage given in second argument.
    #
    # @param [Fixnum] spare_percentage percentage of spare disk space, i.e. free space is increased
    # @return [Array] partition list, e.g.  [$["free":389318, "name":"/", "used":1487222],
    #				     $["free":1974697, "name":"/usr", "used":4227733]]
    #
    # @example EvaluateFreeSpace ( 5 );
    #
    # ***  This is needed during update !
    def EvaluateFreeSpace(spare_percentage)
      partition = []
      # the sizes are in kB
      min_spare = 10 * 1024 # 10 MB
      max_spare = 1024 * 1024 # 1 GB

      target = Installation.destdir

      # get information about diskspace ( used/free space on every partition )
      partition = Convert.convert(
        SCR.Read(path(".run.df")),
        :from => "any",
        :to   => "list <map <string, string>>"
      )

      # filter out headline and other invalid entries
      partition = Builtins.filter(partition) do |part|
        Builtins.substring(Ops.get(part, "name", ""), 0, 1) == "/"
      end

      if Installation.dirinstall_installing_into_dir
        target = GetDirMountPoint(Installation.dirinstall_target, partition)
        Builtins.y2milestone(
          "Installing into a directory, target directory: %1, target mount point: %2",
          Installation.dirinstall_target,
          target
        )
      end

      part_input = []

      Builtins.foreach(partition) do |part|
        part_info = {}
        free_size = 0
        spare_size = 0
        partName = ""
        add_part = true
        mountName = Ops.get_string(part, "name", "")
        spec = Ops.get_string(part, "spec", "")
        if Installation.dirinstall_installing_into_dir
          if Builtins.substring(mountName, 0, 1) != "/"
            mountName = Ops.add("/", mountName)
          end

          dir_target = Installation.dirinstall_target

          Builtins.y2debug(
            "mountName: %1, dir_target: %2",
            mountName,
            dir_target
          )

          if Ops.greater_than(
              Builtins.size(mountName),
              Builtins.size(dir_target)
            ) &&
              Builtins.substring(mountName, 0, Builtins.size(dir_target)) == dir_target
            part_info = Builtins.add(part_info, "name", mountName)
          elsif mountName == target
            part_info = Builtins.add(part_info, "name", "/")
          else
            add_part = false
          end
        elsif target != "/"
          if Ops.greater_or_equal(
              Builtins.size(mountName),
              Builtins.size(target)
            ) &&
              Builtins.substring(mountName, 0, Builtins.size(target)) == target
            partName = Builtins.substring(mountName, Builtins.size(target))
            # nothing left, it was target root itself
            if Builtins.size(partName) == 0
              part_info = Builtins.add(part_info, "name", "/")
            else
              part_info = Builtins.add(part_info, "name", partName)
            end
          else
            add_part = false
          end # target is "/"
        else
          if mountName == "/"
            part_info = Builtins.add(part_info, "name", mountName)
          # ignore some mount points
          elsif mountName != Installation.sourcedir && mountName != "/cdrom" &&
              mountName != "/dev/shm" &&
              spec != "udev" &&
              !Builtins.regexpmatch(mountName, "^/media/") &&
              !Builtins.regexpmatch(mountName, "^var/adm/mount/")
            part_info = Builtins.add(part_info, "name", mountName)
          else
            add_part = false
          end
        end
        if add_part
          part_info = Builtins.add(
            part_info,
            "used",
            Builtins.tointeger(Ops.get_string(part, "used", "0"))
          )

          free_size = Builtins.tointeger(Ops.get_string(part, "free", "0"))
          spare_size = Ops.divide(
            Ops.multiply(free_size, spare_percentage),
            100
          )

          if Ops.less_than(spare_size, min_spare)
            spare_size = min_spare
          elsif Ops.greater_than(spare_size, max_spare)
            spare_size = max_spare
          end

          free_size = Ops.subtract(free_size, spare_size)
          free_size = 0 if Ops.less_than(free_size, 0) # don't add a negative size

          part_info = Builtins.add(part_info, "free", free_size)

          part_input = Builtins.add(part_input, part_info)
        end
      end

      Builtins.y2milestone(
        "UTILS *** EvaluateFreeSpace returns: %1",
        part_input
      )

      Pkg.TargetInitDU(part_input)

      deep_copy(part_input)
    end

    # return default ext3/4 journal size (in B) for target partition size
    def DefaultExtJournalSize(part)
      part = deep_copy(part)
      if Ops.get_symbol(part, "used_fs", :unknown) == :ext2
        Builtins.y2milestone("No journal on ext2")
        return 0
      end

      ret = 0

      part_size = Ops.multiply(1024, Ops.get_integer(part, "size_k", 0))
      # default block size is 4k
      bs = Builtins.tointeger(
        Ops.get_string(
          part,
          ["fs_options", "opt_blocksize", "option_value"],
          "4096"
        )
      )
      blocks = Ops.divide(part_size, bs)

      Builtins.y2milestone(
        "Partition %1: %2 blocks (block size: %3)",
        Ops.get_string(part, "name", ""),
        blocks,
        bs
      )

      # values extracted from ext2fs_default_journal_size() function in e2fsprogs sources
      if Ops.less_than(blocks, 2048)
        ret = 0
      elsif Ops.less_than(blocks, 32768)
        ret = 1024
      elsif Ops.less_than(blocks, 256 * 1024)
        ret = 4096
      elsif Ops.less_than(blocks, 512 * 1024)
        ret = 8192
      elsif Ops.less_than(blocks, 1024 * 1024)
        ret = 16384
      else
        # maximum journal size
        ret = 32768
      end

      # converts blocks to bytes
      ret = Ops.multiply(ret, bs)

      Builtins.y2milestone("Default journal size: %1kB", Ops.divide(ret, 1024))


      ret
    end

    def ExtJournalSize(part)
      part = deep_copy(part)
      if Ops.get_symbol(part, "used_fs", :unknown) == :ext2
        Builtins.y2milestone("No journal on ext2")
        return 0
      end

      ret = 0
      # no journal
      if Builtins.haskey(Ops.get_map(part, "fs_options", {}), "no_journal")
        Builtins.y2milestone(
          "Partition %1 has disabled journal",
          Ops.get_string(part, "name", "")
        )
      else
        Builtins.y2milestone(
          "Using default journal size for %1",
          Ops.get_string(part, "name", "")
        )
        ret = DefaultExtJournalSize(part)
      end
      # Note: custom journal size cannot be entered in the partitioner

      Builtins.y2milestone(
        "Journal size for %1: %2kB",
        Ops.get_string(part, "name", ""),
        Ops.divide(ret, 1024)
      )

      ret
    end

    def XfsJournalSize(part)
      part = deep_copy(part)
      part_size = Ops.multiply(1024, Ops.get_integer(part, "size_k", 0))
      mb = 1 << 20
      gb = 1 << 30

      # the default log size to fs size ratio is 1:2048
      # (the value is then adjusted according to many other fs parameters,
      # we take just the simple approach here, it should be sufficient)
      ret = Ops.divide(part_size, 2048)

      # check min and max limits
      min_log_size = Ops.multiply(10, mb)
      max_log_size = Ops.multiply(2, gb)

      if Ops.less_than(ret, min_log_size)
        ret = min_log_size
      elsif Ops.greater_than(ret, max_log_size)
        ret = max_log_size
      end

      Builtins.y2milestone(
        "Estimated journal size for XFS partition %1kB: %2kB",
        Ops.divide(part_size, 1024),
        Ops.divide(ret, 1024)
      )

      ret
    end

    def ReiserJournalSize(part)
      part = deep_copy(part)
      # the default is 8193 of 4k blocks (max = 32749, min = 513 blocks)
      ret = 8193 * 4096

      Builtins.y2milestone(
        "Default Reiser journal size: %1kB",
        Ops.divide(ret, 1024)
      )

      ret
    end

    def DefaultJfsJournalSize(part_size)
      # the default is 0.4% rounded to megabytes, 128MB max.
      ret = Ops.shift_right(part_size, 8) # 0.4% ~= 1/256
      max = 128 * (1 << 20) # 128 MB

      ret = Ops.shift_left(
        Ops.shift_right(Ops.subtract(Ops.add(ret, 1 << 20), 1), 20),
        20
      )

      ret = max if Ops.greater_than(ret, max)

      Builtins.y2milestone(
        "Default JFS journal size: %1MB",
        Ops.shift_right(ret, 20)
      )

      ret
    end

    def JfsJournalSize(part)
      part = deep_copy(part)
      # log size (in MB)
      log_size = Builtins.tointeger(
        Ops.get_string(
          part,
          ["fs_options", "opt_log_size", "option_value"],
          "0"
        )
      )

      if Ops.greater_than(log_size, 0)
        # convert to bytes
        log_size = Ops.multiply(log_size, 1 << 20)
      else
        log_size = DefaultJfsJournalSize(
          Ops.multiply(1024, Ops.get_integer(part, "size_k", 0))
        )
      end

      Builtins.y2milestone(
        "Jfs journal size: %1MB",
        Ops.shift_right(log_size, 20)
      )

      log_size
    end

    def EstimateTargetUsage(parts)
      parts = deep_copy(parts)
      Builtins.y2milestone("EstimateTargetUsage(%1)", parts)
      mb = 1 << 10 # sizes are in kB, 1MB is 1024 kB

      # invalid or empty input
      if parts == nil || Builtins.size(parts) == 0
        Builtins.y2error("Invalid input: %1", parts)
        return []
      end

      # the numbers are from openSUSE-11.4 default KDE installation
      used_mapping = {
        "/var/lib/rpm"    => Ops.multiply(42, mb), # RPM database
        "/var/log"        => Ops.multiply(14, mb), # system logs (YaST logs have ~12MB)
        "/var/adm/backup" => Ops.multiply(10, mb), # backups
        "/var/cache/zypp" => Ops.multiply(38, mb), # zypp metadata cache after refresh (with OSS + update repos)
        "/etc"            => Ops.multiply(2, mb), # various /etc config files not belonging to any package
        "/usr/share"      => Ops.multiply(1, mb), # some files created by postinstall scripts
        "/boot/initrd"    => Ops.multiply(11, mb)
      } # depends on HW but better than nothing

      Builtins.y2milestone("Adding target size mapping: %1", used_mapping)

      mount_points = []

      # convert list to map indexed by mount point
      mounts = Builtins.listmap(parts) do |part|
        mount_points = Builtins.add(
          mount_points,
          Ops.get_string(part, "name", "")
        )
        { Ops.get_string(part, "name", "") => part }
      end


      Builtins.foreach(used_mapping) do |dir, used|
        mounted = String.FindMountPoint(dir, mount_points)
        Builtins.y2milestone("Dir %1 is mounted on %2", dir, mounted)
        part = Ops.get(mounts, mounted, {})
        if part != {}
          curr_used = Ops.get_integer(part, "used", 0)
          Builtins.y2milestone(
            "Adding %1kB to %2kB currently used",
            used,
            curr_used
          )
          curr_used = Ops.add(curr_used, used)

          Ops.set(part, "used", curr_used)
          Ops.set(
            part,
            "free",
            Ops.subtract(Ops.get_integer(part, "free", 0), used)
          )

          Ops.set(mounts, mounted, part)
        else
          Builtins.y2warning(
            "Cannot find partition for mount point %1, ignoring it",
            mounted
          )
        end
      end 


      # convert back to list
      ret = Builtins.maplist(mounts) { |dir, part| part }

      Builtins.y2milestone("EstimateTargetUsage() result: %1", ret)

      deep_copy(ret)
    end

    # is the filesystem one of Ext2/3/4?
    def ExtFs(fs)
      fs == :ext2 || fs == :ext3 || fs == :ext4
    end

    # return estimated fs overhead
    # (the difference between partition size and reported fs blocks)
    def EstimateFsOverhead(part)
      part = deep_copy(part)
      fs_size = Ops.multiply(1024, Ops.get_integer(part, "size_k", 0))
      fs = Ops.get_symbol(part, "used_fs", :unknown)

      ret = 0

      if ExtFs(fs)
        # ext2/3/4 overhead is about 1.6% according to my test (8GB partition)
        ret = Ops.divide(Ops.multiply(fs_size, 16), 1000)
        Builtins.y2milestone("Estimated Ext2/3/4 overhead: %1kB", ret)
      elsif fs == :xfs
        # xfs overhead is about 0.1%
        ret = Ops.divide(fs_size, 1000)
        Builtins.y2milestone("Estimated XFS overhead: %1kB", ret)
      elsif fs == :jfs
        # jfs overhead is about 0.3%
        ret = Ops.divide(Ops.multiply(fs_size, 3), 1000)
        Builtins.y2milestone("Estimated JFS overhead: %1kB", ret)
      end
      # reiser and btrfs have negligible overhead, just ignore it

      ret
    end

    # return reserved space for root user (in bytes)
    def ReservedSpace(part)
      part = deep_copy(part)
      # read the percentage
      option = Ops.get_string(
        part,
        ["fs_options", "opt_reserved_blocks", "option_value"],
        ""
      )
      ret = 0

      if option != nil && option != ""
        percent = Builtins.tofloat(option)

        if Ops.greater_than(percent, 0.0)
          # convert to absolute value
          fs_size = Ops.get_integer(part, "size_k", 0)
          ret = Builtins.tointeger(
            Ops.multiply(
              Convert.convert(
                Ops.divide(fs_size, 100),
                :from => "integer",
                :to   => "float"
              ),
              percent
            )
          )
        end
      end

      if Ops.greater_than(ret, 0)
        Builtins.y2milestone(
          "Partition %1: reserved space: %2%% (%3kB)",
          Ops.get_string(part, "name", ""),
          option,
          ret
        )
      end

      Ops.multiply(ret, 1024)
    end

    # Define a macro that transforms information about all partitions ( from
    # Storage::GetTargetMap() ) into a list(map) with information about partitions
    # which are available for installation, e.g.:
    #
    # [$["free":1625676, "name":"/boot", "used":0], $["free":2210406, "name":"/", "used":0]]
    #
    # Please note: there isn't any information about used space, so "used" at begin
    #              of installation is initialized with zero;
    #              size "free", "used" in KBytes
    #

    def get_partition_info
      # remove leading slash so it matches the packages.DU path
      remove_slash = true

      if !Stage.initial
        # read /proc/mounts as a list of maps
        # $["file":"/boot", "freq":0, "mntops":"rw", "passno":0, "spec":"/dev/sda1", "vfstype":"ext2"]
        mounts = Convert.convert(
          SCR.Read(path(".proc.mounts")),
          :from => "any",
          :to   => "list <map <string, any>>"
        )
        Builtins.y2milestone("mounts %1", mounts)

        partitions = []
        Builtins.foreach(mounts) do |mpoint|
          name = Ops.get_string(mpoint, "file", "")
          if Builtins.substring(name, 0, 1) == "/" &&
              Builtins.substring(name, 0, 5) != "/dev/" && # filter out /dev/pts etc.
              Ops.get_string(mpoint, "vfstype", "") != "rootfs" # filter out duplicate "/" entry
            capacity = Pkg.TargetCapacity(name)
            if capacity != 0 # dont look at pseudo-devices (proc, shmfs, ...)
              used = Pkg.TargetUsed(name)
              partitions = Builtins.add(
                partitions,
                {
                  "name" => name,
                  "free" => Ops.subtract(capacity, used),
                  "used" => used
                }
              )
            end
          end
        end
        Pkg.TargetInitDU(partitions)
        Builtins.y2milestone("get_partition_info: %1", partitions)
        return deep_copy(partitions)
      end # !Stage::initial ()

      # remove the previous failures
      @failed_mounts = []

      # installation stage - Storage:: is definitely present
      # call Storage::GetTargetMap()
      targets = Convert.convert(
        WFM.call("wrapper_storage", ["GetTargetMap"]),
        :from => "any",
        :to   => "map <string, map>"
      )

      if targets == nil
        Builtins.y2error("Target map is nil, Storage:: is probably missing")
      end

      if Mode.test
        targets = Convert.convert(
          SCR.Read(path(".target.yast2"), "test_target_map.ycp"),
          :from => "any",
          :to   => "map <string, map>"
        )
      end

      target_partitions = []
      min_spare = 20 * 1024 * 1024 # minimum free space ( 20 MB )

      Builtins.foreach(targets) do |disk, diskinfo|
        part_info = Ops.get_list(diskinfo, "partitions", [])
        Builtins.foreach(part_info) do |part|
          Builtins.y2milestone("Adding partition: %1", part)
          used_fs = Ops.get_symbol(part, "used_fs", :unknown)
          # ignore VFAT and NTFS partitions (bnc#)
          if used_fs == :vfat || used_fs == :ntfs
            Builtins.y2warning(
              "Ignoring partition %1 with %2 filesystem",
              Ops.get_string(part, "device", ""),
              used_fs
            )
          else
            free_size = 0

            if Ops.get(part, "mount") != nil &&
                Builtins.substring(Ops.get_string(part, "mount", ""), 0, 1) == "/"
              if Ops.get(part, "create") == true ||
                  Ops.get(part, "delete") == false ||
                  Ops.get(part, "create") == nil &&
                    Ops.get(part, "delete") == nil
                Builtins.y2debug(
                  "get_partition_info: adding partition: %1",
                  part
                )

                # get free_size on partition in kBytes
                free_size = Ops.multiply(
                  Ops.get_integer(part, "size_k", 0),
                  1024
                )
                free_size = Ops.subtract(free_size, min_spare)

                # free_size smaller than min_spare, fix negative value
                if Ops.less_than(free_size, 0)
                  Builtins.y2milestone("Fixing free size: %1 to 0", free_size)
                  free_size = 0
                end

                used = 0
                if !(Ops.get_boolean(part, "create", false) ||
                    Ops.get_boolean(part, "format", false))
                  tmpdir = Convert.to_string(SCR.Read(path(".target.tmpdir")))
                  tmpdir = Ops.add(tmpdir, "/diskspace_mount")
                  SCR.Execute(
                    path(".target.bash"),
                    Builtins.sformat("test -d %1 || mkdir -p %1", tmpdir)
                  )

                  # TODO: Use the functions provided by yast2-storage to query free space.

                  # mount in read-only mode (safer)
                  mount_options = ["ro"]

                  # add "nolock" if it's a NFS share (bnc#433893)
                  if used_fs == :nfs
                    Builtins.y2milestone("Mounting NFS with 'nolock' option")
                    mount_options = Builtins.add(mount_options, "nolock")
                  end

                  # join the options
                  mount_options_str = Builtins.mergestring(mount_options, ",")

                  mount_command = Builtins.sformat(
                    "/bin/mount -o %1 %2 %3",
                    mount_options_str,
                    Ops.get_string(part, "device", ""),
                    tmpdir
                  )

                  log.info("Executing mount command: #{mount_command}")
                  result = SCR.Execute(path(".target.bash"), mount_command)
                  log.info("Mount result: #{result}")

                  if result == 0
                    partition = Convert.convert(
                      SCR.Read(path(".run.df")),
                      :from => "any",
                      :to   => "list <map <string, string>>"
                    )
                    Builtins.foreach(partition) do |p|
                      if Ops.get_string(p, "name", "") == tmpdir
                        Builtins.y2milestone("P: %1", p)
                        free_size = Ops.multiply(
                          Builtins.tointeger(Ops.get_string(p, "free", "0")),
                          1024
                        )
                        used = Ops.multiply(
                          Builtins.tointeger(Ops.get_string(p, "used", "0")),
                          1024
                        )
                      end
                    end
                    result = SCR.Execute(path(".target.bash"), "/bin/umount #{tmpdir}")
                    if result != 0
                      log.error("Umount failed, result: #{result}")
                    end
                  else
                    Builtins.y2error(
                      "Mount failed, ignoring partition %1",
                      Ops.get_string(part, "device", "")
                    )
                    @failed_mounts = Builtins.add(@failed_mounts, part)

                    next
                  end
                else
                  # for formatted partitions estimate free system size
                  # compute fs overhead
                  used = EstimateFsOverhead(part)

                  if Ops.greater_than(used, 0)
                    Builtins.y2milestone(
                      "Partition %1: assuming fs overhead: %2kB",
                      Ops.get_string(part, "device", ""),
                      Ops.divide(used, 1024)
                    )
                  end

                  # journal size
                  js = 0

                  if ExtFs(used_fs)
                    js = ExtJournalSize(part)
                    reserved = ReservedSpace(part)

                    if Ops.greater_than(reserved, 0)
                      used = Ops.add(used, reserved)
                    end
                  elsif used_fs == :xfs
                    js = XfsJournalSize(part)
                  elsif used_fs == :reiser
                    js = ReiserJournalSize(part)
                  elsif used_fs == :jfs
                    js = JfsJournalSize(part)
                  else
                    Builtins.y2warning(
                      "Unknown journal size for filesystem: %1",
                      used_fs
                    )
                  end

                  if Ops.greater_than(js, 0)
                    Builtins.y2milestone(
                      "Partition %1: assuming journal size: %2kB",
                      Ops.get_string(part, "device", ""),
                      Ops.divide(js, 1024)
                    )
                    used = Ops.add(used, js)
                  end

                  # decrease free size
                  free_size = Ops.subtract(free_size, used)

                  # check for underflow
                  if Ops.less_than(free_size, 0)
                    Builtins.y2milestone("Fixing free size: %1 to 0", free_size)
                    free_size = 0
                  end
                end

                # convert into kB for TargetInitDU
                free_size = Ops.divide(free_size, 1024)
                used = Ops.divide(used, 1024)

                Builtins.y2milestone(
                  "available partition: mount: %1, free: %2 KB, used: %3 KB",
                  Ops.get_string(part, "mount", ""),
                  free_size,
                  used
                )
                if !remove_slash
                  target_partitions = Builtins.add(
                    target_partitions,
                    {
                      "name" => Ops.get_string(part, "mount", ""),
                      "used" => used,
                      "free" => free_size
                    }
                  )
                else
                  part_name = ""
                  mount_name = Ops.get_string(part, "mount", "")

                  if mount_name != "/"
                    part_name = Builtins.substring(
                      mount_name,
                      1,
                      Builtins.size(mount_name)
                    )
                  else
                    part_name = mount_name
                  end

                  target_partitions = Builtins.add(
                    target_partitions,
                    { "name" => part_name, "used" => used, "free" => free_size }
                  )
                end
              end
            end
          end
        end # foreach (`part)
      end # foreach (`disk)

      # add estimated size occupied by non-package files
      target_partitions = EstimateTargetUsage(target_partitions)

      Builtins.y2milestone("get_partition_info: part %1", target_partitions)
      Pkg.TargetInitDU(target_partitions)

      deep_copy(target_partitions)
    end

    # Get information about available partitions either from "targetMap"
    # in case of a new installation or from 'df' command (continue mode
    # and installation on installed system).
    # Returns a list containing available partitions and stores the list
    # in "partition_info".
    #
    # @return list partition list, e.g.  [$["free":389318, "name":"/", "used":1487222],
    #				     $["free":1974697, "name":"usr", "used":4227733]]
    #
    #
    # @example GetPartitionInfo();
    #
    # Will be called from Packages when re-doing proposal !!
    def GetPartitionInfo
      partition = []

      if Stage.cont
        partition = EvaluateFreeSpace(0) # free spare already checked during first part of installation
      elsif Mode.update
        partition = EvaluateFreeSpace(15) # 15% free spare for update/upgrade
      elsif Mode.normal
        partition = EvaluateFreeSpace(5) # 5% free spare for post installation # Stage::initial ()
      else
        partition = get_partition_info
      end
      Builtins.y2milestone(
        "INIT done, SpaceCalculation - partitions: %1",
        partition
      )

      @info_called = true
      @partition_info = deep_copy(partition) # store partition_info

      deep_copy(partition)
    end



    # get current space data for partitions
    # current_partitions = list of maps of
    # $["format":bool, "free":integer, "name" : string, "used" :integer, "used_fs": symbol]
    # from Storage module
    # returns list of maps of
    # $["name" : string, "free" : integer, "used" : integer ]
    #
    def CheckCurrentSpace(current_partitions)
      current_partitions = deep_copy(current_partitions)
      output = []

      Builtins.foreach(current_partitions) do |par|
        outdata = {}
        Ops.set(outdata, "name", Ops.get_string(par, "name", ""))
        Ops.set(
          outdata,
          "used",
          Pkg.TargetUsed(
            Ops.add(Installation.destdir, Ops.get_string(par, "name", ""))
          )
        )
        Ops.set(
          outdata,
          "free",
          Ops.subtract(
            Pkg.TargetCapacity(
              Ops.add(Installation.destdir, Ops.get_string(par, "name", ""))
            ),
            Ops.get_integer(outdata, "used", 0)
          )
        )
        output = Builtins.add(output, Builtins.eval(outdata))
      end
      Builtins.y2milestone(
        "CheckCurrentSpace(%1) = %2",
        current_partitions,
        output
      )

      deep_copy(output)
    end

    def GetPartitionWarning
      GetPartitionInfo() if !@info_called
      used = 0
      message = []

      #$[ "dir" : [ total, usednow, usedfuture ], .... ]

      Builtins.foreach(Pkg.TargetGetDU) do |dir, sizelist|
        Builtins.y2milestone(
          "dir %1, sizelist (total, current, future) %2",
          dir,
          sizelist
        )
        needed = Ops.subtract(
          Ops.get_integer(sizelist, 2, 0),
          Ops.get_integer(sizelist, 0, 0)
        ) # usedfuture - total
        if Ops.greater_than(needed, 0)
          # Warning message, e.g.: Partition /usr needs 35 MB more disk space
          message = Builtins.add(
            message,
            Builtins.sformat(
              _("Partition \"%1\" needs %2 more disk space."),
              # needed is in kB
              dir,
              String.FormatSize(Ops.multiply(needed, 1024))
            )
          )
        end
        used = Ops.add(used, Ops.get_integer(sizelist, 2, 0))
      end

      Builtins.y2debug("Total used space (kB): %1", used)

      if Ops.greater_than(Builtins.size(message), 0)
        # dont ask user to deselect packages for imap server, product
        if ProductFeatures.GetFeature("software", "selection_type") == :auto
          if Mode.update
            message = Builtins.add(
              message,
              "\n" +
                # popup message
                _(
                  "Deselect packages or delete data or temporary files\nbefore updating the system.\n"
                )
            )
          else
            message = Builtins.add(
              message,
              "\n" +
                # popup message
                _("Deselect some packages.")
            )
          end
        end
      end
      deep_copy(message)
    end

    #
    # Popup displays warning about exhausted disk space
    #
    def ShowPartitionWarning
      message = GetPartitionWarning()
      if Ops.greater_than(Builtins.size(message), 0)
        Builtins.y2warning("Warning: %1", message)
        Report.Message(Builtins.mergestring(message, "\n"))
        return true
      else
        return false
      end
    end


    #
    # Calculate required disk space
    #
    def GetRequSpace(initialize)
      GetPartitionInfo() if !@info_called

      # used space in kB
      used = 0

      #$[ "dir" : [ total, usednow, usedfuture ], .... ]
      Builtins.foreach(Pkg.TargetGetDU) do |dir, sizelist|
        used = Ops.add(used, Ops.get_integer(sizelist, 2, 0))
      end
      Builtins.y2milestone("GetReqSpace Pkg::TargetGetDU() %1", Pkg.TargetGetDU)
      # used is in kB
      String.FormatSize(Ops.multiply(used, 1024))
    end


    #
    # Check, if the current selection fits on the disk
    # return true or false
    #
    def CheckDiskSize
      fit = true

      GetPartitionInfo() if !@info_called

      used = 0

      message = ""
      #$[ "dir" : [ total, usednow, usedfuture ], .... ]
      Builtins.foreach(Pkg.TargetGetDU) do |dir, sizelist|
        Builtins.y2milestone("%1: %2", dir, sizelist)
        needed = Ops.subtract(
          Ops.get_integer(sizelist, 2, 0),
          Ops.get_integer(sizelist, 0, 0)
        ) # usedfuture - total
        if Ops.greater_than(needed, 0)
          Builtins.y2warning(
            "Partition \"%1\" needs %2 more disk space.",
            # size is in kB
            dir,
            String.FormatSize(Ops.multiply(needed, 1024))
          )
          fit = false
        end
        used = Ops.add(used, Ops.get_integer(sizelist, 2, 0))
      end

      Builtins.y2milestone("Total used space (kB): %1, fits ?: %2", used, fit)

      fit
    end

    # Check, if there is enough free space after installing the current selection
    # @param [Fixnum] free_percent minimal free space after installation (in percent)
    # @return [Array] of partitions which have less than free_percent free size
    def CheckDiskFreeSpace(free_percent, max_unsufficient_free_size)
      GetPartitionInfo() if !@info_called

      Builtins.y2milestone(
        "min. free space: %1%%, max. unsufficient free space: %2",
        free_percent,
        max_unsufficient_free_size
      )

      ret = []

      if Ops.greater_than(free_percent, 0)
        #$[ "dir" : [ total, usednow, usedfuture ], .... ]
        Builtins.foreach(Pkg.TargetGetDU) do |dir, sizelist|
          Builtins.y2milestone("Disk usage of directory %1: %2", dir, sizelist)
          total = Ops.get_integer(sizelist, 0, 0)
          used_future = Ops.get_integer(sizelist, 2, 0)
          used_now = Ops.get_integer(sizelist, 1, 0)
          current_free_size = Ops.subtract(total, used_future)
          current_free_percent = Ops.divide(
            Ops.multiply(current_free_size, 100),
            total
          )
          # ignore the partitions which were already full and no files will be installed there (bnc#259493)
          if Ops.greater_than(used_future, used_now) &&
              Ops.greater_than(current_free_size, 0)
            if Ops.less_than(current_free_percent, free_percent) &&
                Ops.less_than(current_free_size, max_unsufficient_free_size)
              Builtins.y2warning(
                "Partition %1: less than %2%% free space (%3%%, %4)",
                dir,
                free_percent,
                current_free_percent,
                current_free_size
              )

              ret = Builtins.add(
                ret,
                {
                  "dir"          => dir,
                  "free_percent" => current_free_percent,
                  "free_size"    => current_free_size
                }
              )
            end
          end
        end
      end

      Builtins.y2milestone("Result: %1", ret)

      deep_copy(ret)
    end

    publish :function => :GetPartitionList, :type => "list ()"
    publish :function => :GetFailedMounts, :type => "list <map> ()"
    publish :function => :EvaluateFreeSpace, :type => "list <map <string, any>> (integer)"
    publish :function => :GetPartitionInfo, :type => "list ()"
    publish :function => :CheckCurrentSpace, :type => "list (list <map>)"
    publish :function => :GetPartitionWarning, :type => "list <string> ()"
    publish :function => :ShowPartitionWarning, :type => "boolean ()"
    publish :function => :GetRequSpace, :type => "string (boolean)"
    publish :function => :CheckDiskSize, :type => "boolean ()"
    publish :function => :CheckDiskFreeSpace, :type => "list <map> (integer, integer)"
  end

  SpaceCalculation = SpaceCalculationClass.new
  SpaceCalculation.main
end
