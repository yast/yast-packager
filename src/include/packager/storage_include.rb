# encoding: utf-8

# File:	include/packager/storage_include.ycp
# Module:	Packager
# Summary:	Storage calls
# Authors:	Lukas Ocilka <locilka@suse.cz>
#
# $Id$
#
module Yast
  module PackagerStorageIncludeInclude
    def initialize_packager_storage_include(include_target)
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

      nil
    end
  end
end
