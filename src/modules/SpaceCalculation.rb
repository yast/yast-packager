# Module:    SpaceCalculation.ycp
#
# Authors:    Klaus Kaempf (kkaempf@suse.de)
#      Gabriele Strattner (gs@suse.de)
#      Stefan Schubert (schubi@suse.de)
#
#

require "yast"
require "shellwords"
require "fileutils"
require "y2storage"
require "y2packager/storage_manager_proxy"

# Yast namespace
module Yast
  # Package installation functions usable
  # when the installation media is available
  # on Installation::sourcedir
  class SpaceCalculationClass < Module
    include Yast::Logger

    # 16 MiB (in KiB)
    MIN_SPARE_KIB = 16 * 1024
    # 1 GiB (in KiB)
    MAX_SPARE_KIB = 1 * 1024 * 1024

    # 1 MiB in KiB
    MIB = 1024

    TARGET_FS_TYPES_TO_IGNORE = [
      Y2Storage::Filesystems::Type::VFAT,
      Y2Storage::Filesystems::Type::NTFS
    ].freeze

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
    #             $["free":1974697, "name":"/usr", "used":4227733]]
    #
    # @example EvaluateFreeSpace ( 5 );
    #
    # ***  This is needed during update !
    def EvaluateFreeSpace(spare_percentage)
      target = Installation.destdir

      # get information about diskspace ( used/free space on every partition )
      partitions = SCR.Read(path(".run.df"))

      # filter out headline and other invalid entries
      partitions.select! { |p| p["name"].start_with?("/") }

      log.info "df result: #{partitions}"

      # TODO: FIXME dirinstall has been dropped, probably drop this block completely
      if Installation.dirinstall_installing_into_dir
        target = GetDirMountPoint(Installation.dirinstall_target, partitions)
        log.info "Installing into a directory, target directory: " \
          "#{Installation.dirinstall_target}, target mount point: #{target}"
      end

      du_partitions = []

      partitions.each do |part|
        part_info = {}
        mountName = part["name"] || ""

        # TODO: FIXME dirinstall has been dropped, probably drop this block completely?
        if Installation.dirinstall_installing_into_dir
          mountName.prepend("/") unless mountName.start_with?("/")
          dir_target = Installation.dirinstall_target

          log.debug "mountName: #{mountName}, dir_target: #{dir_target}"

          if mountName.start_with?(dir_target)
            part_info["name"] = mountName
          elsif mountName == target
            part_info["name"] = "/"
          end
        elsif target != "/"
          if mountName.start_with?(target)
            partName = mountName[target.size..-1]
            # nothing left, it was target root itself
            part_info["name"] = partName.empty? ? "/" : partName
          end # target is "/"
        elsif mountName == "/"
          part_info["name"] = mountName
        # ignore some mount points
        elsif mountName != Installation.sourcedir && mountName != "/cdrom" &&
            mountName != "/dev/shm" &&
            part["spec"] != "udev" &&
            !mountName.start_with?("/media/") &&
            !mountName.start_with?("/run/media/") &&
            !mountName.start_with?("/var/adm/mount/")
          part_info["name"] = mountName
        end

        next if part_info.empty?

        filesystem = part["type"]
        part_info["filesystem"] = filesystem

        if filesystem == "btrfs"
          log.info "Detected btrfs at #{mountName}"
          btrfs_used_kib = btrfs_used_size(mountName) / 1024
          log.info "Difference to 'df': #{(part["used"].to_i - btrfs_used_kib) / 1024}MiB"
          part_info["used"] = btrfs_used_kib
          part_info["growonly"] = btrfs_snapshots?(mountName)
          total_kb = part["whole"].to_i
          free_size_kib = total_kb - btrfs_used_kib
        else
          part_info["used"] = part["used"].to_i
          free_size_kib = part["free"].to_i
          part_info["growonly"] = false
        end

        spare_size_kb = free_size_kib * spare_percentage / 100

        if spare_size_kb < MIN_SPARE_KIB
          spare_size_kb = MIN_SPARE_KIB
        elsif spare_size_kb > MAX_SPARE_KIB
          spare_size_kb = MAX_SPARE_KIB
        end

        free_size_kib -= spare_size_kb
        # don't use a negative size
        free_size_kib = 0 if free_size_kib < 0

        part_info["free"] = free_size_kib

        du_partitions << part_info
      end

      log.info "UTILS *** EvaluateFreeSpace returns: #{du_partitions}"
      Pkg.TargetInitDU(du_partitions)

      du_partitions
    end

    # return default ext3/4 journal size (in B) for target partition size
    def DefaultExtJournalSize(filesystem)
      if filesystem.to_s == "ext2"
        Builtins.y2milestone("No journal on ext2")
        return 0
      end

      bs = filesystem.blk_devices[0].region.block_size.to_i
      blocks = Ops.divide(filesystem_size(filesystem), bs)

      Builtins.y2milestone(
        "Partition %1: %2 blocks (block size: %3)",
        filesystem_dev_name(filesystem),
        blocks,
        bs
      )

      # values extracted from ext2fs_default_journal_size() function in e2fsprogs sources
      ret = if Ops.less_than(blocks, 2048)
        0
      elsif Ops.less_than(blocks, 32768)
        1024
      elsif Ops.less_than(blocks, 256 * 1024)
        4096
      elsif Ops.less_than(blocks, 512 * 1024)
        8192
      elsif Ops.less_than(blocks, 1024 * 1024)
        16384
      else
        # maximum journal size
        32768
      end

      # converts blocks to bytes
      ret = Ops.multiply(ret, bs)

      Builtins.y2milestone("Default journal size: %1kB", Ops.divide(ret, 1024))

      ret
    end

    def ExtJournalSize(filesystem)
      if filesystem.to_s == "ext2"
        Builtins.y2milestone("No journal on ext2")
        return 0
      end

      ret = 0
      if filesystem.tune_options.include?("has_journal")
        Builtins.y2milestone(
          "Using default journal size for %1",
          filesystem_dev_name(filesystem)
        )
        ret = DefaultExtJournalSize(filesystem)
      else
        Builtins.y2milestone(
          "Partition %1 has disabled journal",
          filesystem_dev_name(filesystem)
        )
      end
      # Note: custom journal size cannot be entered in the partitioner

      Builtins.y2milestone(
        "Journal size for %1: %2kB",
        filesystem_dev_name(filesystem),
        Ops.divide(ret, 1024)
      )

      ret
    end

    def XfsJournalSize(filesystem)
      part_size = filesystem_size(filesystem)
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

    def ReiserJournalSize(_filesystem)
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

    def JfsJournalSize(filesystem)
      # In the past we used to check the journal size for the particular
      # filesystem. JFS is not supported anymore, so now we simply assume the
      # default size.
      log_size = DefaultJfsJournalSize(filesystem_size(filesystem))

      Builtins.y2milestone(
        "Jfs journal size: %1MB",
        Ops.shift_right(log_size, 20)
      )

      log_size
    end

    def EstimateTargetUsage(parts)
      parts = deep_copy(parts)
      log.info "EstimateTargetUsage(#{parts})"

      # invalid or empty input
      if parts.nil? || parts.empty?
        log.error "Invalid input: #{parts.inspect}"
        return []
      end

      # the numbers are from openSUSE-11.4 default KDE installation
      used_mapping = {
        "/var/lib/rpm"    => 42 * MIB, # RPM database
        "/var/log"        => 14 * MIB, # system logs (YaST logs have ~12MB)
        "/var/adm/backup" => 10 * MIB, # backups
        "/var/cache/zypp" => 38 * MIB, # zypp metadata cache after refresh (with OSS + update repos)
        "/etc"            => 2 * MIB, # various /etc config files not belonging to any package
        "/usr/share"      => 1 * MIB, # some files created by postinstall scripts
        "/boot/initrd"    => 11 * MIB # depends on HW but better than nothing
      }

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
      ret = Builtins.maplist(mounts) { |_dir, part| part }

      Builtins.y2milestone("EstimateTargetUsage() result: %1", ret)

      deep_copy(ret)
    end

    # is the filesystem one of Ext2/3/4?
    def ExtFs(filesystem)
      [:ext2, :ext3, :ext4].include?(filesystem)
    end

    # return estimated fs overhead
    # (the difference between partition size and reported fs blocks)
    def EstimateFsOverhead(filesystem)
      fs_size = filesystem_size(filesystem)
      fs = filesystem.type.to_sym
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
    def ReservedSpace(filesystem)
      # read the percentage

      # storage-ng
      # libstorage-ng simply provides Filesystem#mkfs_options
      # It's up to yast2-storage to store something meaningful there while
      # creating the filesystem. So far we don't do it.
      # TODO: revisit this when we have proper management of the mkfs_options
      option = ""
      #       option = part["fs_options"]["opt_reserved_blocks"]["option_value"] || ""

      ret = 0

      if !option.nil? && option != ""
        percent = Builtins.tofloat(option)

        if Ops.greater_than(percent, 0.0)
          # convert to absolute value
          fs_size = filesystem_size(filesystem)
          ret = Builtins.tointeger(
            Ops.multiply(
              Convert.convert(
                Ops.divide(fs_size, 100),
                from: "integer",
                to:   "float"
              ),
              percent
            )
          )
        end
      end

      if Ops.greater_than(ret, 0)
        Builtins.y2milestone(
          "Partition %1: reserved space: %2%% (%3kB)",
          filesystem_dev_name(filesystem),
          option,
          ret
        )
      end

      Ops.multiply(ret, 1024)
    end

    # Define a macro that transforms information about all partitions (from the
    # staging devicegraph) into a list(map) with information about partitions
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
        # $["file":"/boot", "freq":0, "mntops":"rw", "passno":0,
        #   "spec":"/dev/sda1", "vfstype":"ext2"]
        mounts = SCR.Read(path(".proc.mounts"))
        log.info "mounts #{mounts}"

        partitions = []
        mounts.each do |mpoint|
          name = mpoint["file"]
          filesystem = mpoint["vfstype"]

          next if !name.start_with?("/")
          # filter out /dev/pts etc.
          next if name.start_with?("/dev/")
          # filter out duplicate "/" entry
          next if filesystem == "rootfs"

          capacity = Pkg.TargetCapacity(name)

          next unless capacity.nonzero? # dont look at pseudo-devices (proc, shmfs, ...)

          used = Pkg.TargetUsed(name)
          growonly = false

          if filesystem == "btrfs"
            log.info "Btrfs file system detected at #{name}"
            growonly = btrfs_snapshots?(name)
            log.info "Snapshots detected: #{growonly}"
            new_used = btrfs_used_size(name) / 1024
            log.info "Updated the used size by 'btrfs' utility " \
              "from #{used} to #{new_used} (diff: #{new_used - used})"
            used = new_used
          end

          partitions << {
            "name"       => name,
            "free"       => capacity - used,
            "used"       => used,
            "filesystem" => filesystem,
            "growonly"   => growonly
          }
        end
        Pkg.TargetInitDU(partitions)
        Builtins.y2milestone("get_partition_info: %1", partitions)
        return partitions
      end # !Stage::initial ()

      # remove the previous failures
      @failed_mounts = []

      target_partitions = []
      min_spare = 20 * 1024 * 1024 # minimum free space ( 20 MB )

      target_filesystems.each do |filesystem|
        # storage-ng
        # FIXME
        # With storage-ng we need way less nesting to reach the meaningful
        # information in the data structure (4 fewer levels!). Still, we are
        # temporarily keeping the old indentation here (even if it breaks our
        # coding standard) to avoid confusing developers and git about what had
        # really changed in the code below.
        # This should be fixed when merging storage-ng into master.
        used_fs = filesystem.to_s.to_sym
        free_size = 0
        growonly = false

        log.debug "get_partition_info: adding filesystem: #{filesystem.inspect}"

        # get free_size on partition in kBytes
        free_size = filesystem_size(filesystem)
        free_size -= min_spare

        # free_size smaller than min_spare, fix negative value
        if free_size < 0
          log.info "Fixing free size: #{free_size} to 0"
          free_size = 0
        end

        used = 0
        # If reusing a previously existent filesystem
        if filesystem.exists_in_raw_probed?

          # Mount the filesystem to check the available space.

          tmpdir = SCR.Read(path(".target.tmpdir")) + "/diskspace_mount"
          ::FileUtils.mkdir_p(tmpdir)

          # mount options determined by partitioner
          mount_options = filesystem.mount_options

          # mount in read-only mode (safer)
          mount_options << "ro"

          # add "nolock" if it's a NFS share (bnc#433893)
          if used_fs == :nfs
            log.info "Mounting NFS with 'nolock' option"
            mount_options << "nolock"
          end

          # join the options
          mount_options_str = mount_options.uniq.join(",")

          # Use DM device if it's encrypted, plain device otherwise
          # (bnc#889334)
          # device = part["crypt_device"] || part["device"] || ""
          device = filesystem_dev_name(filesystem)

          mount_command = "/usr/bin/mount -o #{mount_options_str} " \
            "#{Shellwords.escape(device)} #{Shellwords.escape(tmpdir)}"

          log.info "Executing mount command: #{mount_command}"

          result = SCR.Execute(path(".target.bash"), mount_command)
          log.info "Mount result: #{result}"

          if result.zero?
            # specific handler for btrfs
            if used_fs == :btrfs
              used = btrfs_used_size(tmpdir)
              free_size -= used
              growonly = btrfs_snapshots?(tmpdir)
            else
              partition = SCR.Read(path(".run.df"))

              Builtins.foreach(partition) do |p|
                if p["name"] == tmpdir
                  log.info "Partition: #{p}"
                  free_size = p["free"].to_i * 1024
                  used = p["used"].to_i * 1024
                end
              end
            end

            SCR.Execute(path(".target.bash"), "/usr/bin/umount #{Shellwords.escape(tmpdir)}")
          else
            log.error "Mount failed, ignoring partition #{device}"
            @failed_mounts << filesystem

            next
          end
        else
          # for formatted partitions estimate free system size
          # compute fs overhead
          used = EstimateFsOverhead(filesystem)
          device = filesystem_dev_name(filesystem)
          log.info "#{device}: assuming fs overhead: #{used / 1024}KiB"

          # get the journal size
          case used_fs
          when :ext2, :ext3, :ext4
            js = ExtJournalSize(filesystem)
            reserved = ReservedSpace(filesystem)
            used += reserved if reserved > 0
          when :xfs
            js = XfsJournalSize(filesystem)
          when :reiserfs
            js = ReiserJournalSize(filesystem)
          when :jfs
            js = JfsJournalSize(filesystem)
          when :btrfs
            # Btrfs uses temporary trees instead of a fixed journal,
            # there is no journal, it's a logging FS
            # http://en.wikipedia.org/wiki/Btrfs#Log_tree
            js = 0
          else
            log.warn "Unknown journal size for filesystem: #{used_fs}"
          end

          if js && js > 0
            log.info "Partition #{device}: assuming journal size: #{js / 1024}KiB"
            used += js
          end

          # decrease free size
          free_size -= used

          # check for underflow
          if free_size < 0
            log.info "Fixing free size: #{free_size} to 0"
            free_size = 0
          end
        end

        # convert into KiB for TargetInitDU
        free_size_kib = free_size / 1024
        used_kib = used / 1024

        mount_name = filesystem.mount_path
        log.info "partition: mount: #{mount_name}, free: #{free_size_kib}KiB, used: #{used_kib}KiB"

        mount_name = mount_name[1..-1] if remove_slash && mount_name != "/"

        target_partitions << {
          "filesystem" => used_fs.to_s,
          "growonly"   => growonly,
          "name"       => mount_name,
          "used"       => used_kib,
          "free"       => free_size_kib
        }
        # storage-ng: end of indentation gap (see comment above)
      end

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
    #             $["free":1974697, "name":"usr", "used":4227733]]
    #
    #
    # @example GetPartitionInfo();
    #
    # Will be called from Packages when re-doing proposal !!
    def GetPartitionInfo
      partition = []

      partition = if Stage.cont
        # free spare already checked during first part of installation
        EvaluateFreeSpace(0)
      elsif Mode.update
        EvaluateFreeSpace(15) # 15% free spare for update/upgrade
      elsif Mode.normal
        EvaluateFreeSpace(5) # 5% free spare for post installation # Stage::initial ()
      else
        get_partition_info
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

      # $[ "dir" : [ total, usednow, usedfuture ], .... ]

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
          message = if Mode.update
            Builtins.add(
              message,
              "\n" +
                # popup message
                _(
                  "Deselect packages or delete data or temporary files\n" \
                    "before updating the system.\n"
                )
            )
          else
            Builtins.add(
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
        true
      else
        false
      end
    end

    #
    # Calculate required disk space
    #
    def GetRequSpace(_initialize)
      GetPartitionInfo() if !@info_called

      # used space in kB
      used = 0

      # $[ "dir" : [ total, usednow, usedfuture ], .... ]
      Builtins.foreach(Pkg.TargetGetDU) do |_dir, sizelist|
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

      # $[ "dir" : [ total, usednow, usedfuture ], .... ]
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
        # $[ "dir" : [ total, usednow, usedfuture ], .... ]
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
          # ignore the partitions which were already full
          # and no files will be installed there (bnc#259493)
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
                "dir"          => dir,
                "free_percent" => current_free_percent,
                "free_size"    => current_free_size
              )
            end
          end
        end
      end

      Builtins.y2milestone("Result: %1", ret)

      deep_copy(ret)
    end

    publish function: :GetPartitionList, type: "list ()"
    publish function: :GetFailedMounts, type: "list <map> ()"
    publish function: :EvaluateFreeSpace, type: "list <map <string, any>> (integer)"
    publish function: :GetPartitionInfo, type: "list ()"
    publish function: :CheckCurrentSpace, type: "list (list <map>)"
    publish function: :GetPartitionWarning, type: "list <string> ()"
    publish function: :ShowPartitionWarning, type: "boolean ()"
    publish function: :GetRequSpace, type: "string (boolean)"
    publish function: :CheckDiskSize, type: "boolean ()"
    publish function: :CheckDiskFreeSpace, type: "list <map> (integer, integer)"

    # check whether the Btrfs filesystem at the specified directory contains
    # any snapshot (in any subvolume)
    # @param [String] directory mounted directory with Btrfs
    # @return [Boolean] true when a snapshot is found
    def btrfs_snapshots?(directory)
      # list available snapshot subvolumes
      ret = SCR.Execute(path(".target.bash_output"),
        "btrfs subvolume list -s #{Shellwords.escape(directory)}")

      if (ret["exit"]).nonzero?
        log.error "btrfs call failed: #{ret}"
        raise "Cannot detect Btrfs snapshots, subvolume listing failed : #{ret["stderr"]}"
      end

      snapshots = ret["stdout"].split("\n")
      log.info "Found #{snapshots.size} btrfs snapshots"
      log.debug "Snapshots: #{snapshots}"

      !snapshots.empty?
    end

    # @param [String] directory mounted directory with Btrfs
    # @return [Integer] used size in bytes
    def btrfs_used_size(directory)
      ret = SCR.Execute(path(".target.bash_output"),
        "LC_ALL=C btrfs filesystem df #{Shellwords.escape(directory)}")

      if (ret["exit"]).nonzero?
        log.error "btrfs call failed: #{ret}"
        raise "Cannot detect Btrfs disk usage: #{ret["stderr"]}"
      end

      df_info = ret["stdout"].split("\n")
      log.info "Usage reported by btrfs: #{df_info}"

      # sum the "used" sizes
      used = df_info.reduce(0) do |acc, line|
        size = line[/used=(\S+)/, 1]
        size = size ? size_from_string(size) : 0
        acc + size
      end

      log.info "Detected total used size: #{used} (#{used / 1024 / 1024}MiB)"
      used
    end

    # Convert textual size with optional unit suffix into a number
    # @example
    #   size_from_string("2.45MiB") => 2569011
    # @param size_str [String] input value in format "<number>[<space>][<unit>]"
    # where unit can be one of: "" (none) or "B", "KiB", "MiB", "GiB", "TiB", "PiB"
    # @return [Integer] size in bytes
    def size_from_string(size_str)
      # Assume bytes by default
      size_str += "B" unless size_str =~ /[[:alpha:]]/
      Y2Storage::DiskSize.parse(size_str).to_i
    end

  private

    # Filesystems to consider while checking the system available space
    #
    # @return [Array<Storage::Filesystem>]
    def target_filesystems
      filesystems = Y2Storage::Filesystems::BlkFilesystem.all(staging_devicegraph)
      filesystems.select! do |fs|
        # Ignore the devices mounted before starting the installer (e.g. the
        # installation repository mounted by linuxrc when installing from HDD or
        # the user mounted devices like for remote logging). Such devices will
        # not be saved in the final /etc/fstab therefore check the persistency.
        # Check this only in the initial installation (as the non-fstab values
        # will be missing in "/mnt"), in installed system they will stay available
        # at "/". See bsc#1073696 for details.
        log.debug("Persistent #{fs.mount_path.inspect}: #{fs.persistent?}") if fs.mount_path

        fs.mount_path&.start_with?("/") && (!Stage.initial || fs.persistent?)
      end
      filesystems.reject! { |fs| TARGET_FS_TYPES_TO_IGNORE.include?(fs.type) }
      filesystems
    end

    def staging_devicegraph
      @storage_manager ||= Y2Packager::StorageManagerProxy.new
      @storage_manager.staging
    end

    def filesystem_size(filesystem)
      blk_device = filesystem.blk_devices[0]
      # Only for local fs, NFS not supported yet in libstorage-ng
      return 0 unless blk_device

      blk_device.size.to_i
    end

    def filesystem_dev_name(filesystem)
      filesystem.blk_devices[0].name
    end
  end

  SpaceCalculation = SpaceCalculationClass.new
  SpaceCalculation.main
end
