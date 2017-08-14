# encoding: utf-8
module Yast
  # Storage calls
  module PackagerStorageIncludeInclude
    def initialize_packager_storage_include(_include_target)
      textdomain "installation"

      Yast.import "SourceManager"
    end

    # Function releases the the device when EVMS is used and the install
    # source is disk. See bugzilla 208222 for more details.
    def ReleaseHDDUsedAsInstallationSource
      install_src_partition = SourceManager.InstallationSourceOnPartition
      if install_src_partition != ""
        if !Builtins.regexpmatch(install_src_partition, "/dev/")
          install_src_partition = Builtins.sformat(
            "/dev/%1",
            install_src_partition
          )
        end

        Builtins.y2milestone(
          "Calling Storage::RemoveDmMapsTo(%1)",
          install_src_partition
        )
        ret = WFM.call(
          "wrapper_storage",
          ["RemoveDmMapsTo", [install_src_partition]]
        )
        Builtins.y2milestone(
          "Storage::RemoveDmMapsTo(%1) result: %2",
          install_src_partition,
          ret
        )
      end

      nil
    end
  end
end
