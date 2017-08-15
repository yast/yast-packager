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
      end

      Builins.y2milestone "install src partition #{install_src_partition}"

      nil
    end
  end
end
