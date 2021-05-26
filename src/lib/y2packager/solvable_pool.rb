# ------------------------------------------------------------------------------
# Copyright (c) 2019 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require "etc"
require "solv"
require "yast"

module Y2Packager
  # This is a wrapper for the Solv::Pool class
  class SolvablePool
    include Yast::Logger

    def initialize
      @pool = Solv::Pool.new
      @pool.setarch(arch)
    end

    #
    # Load repository metadata to the pool.
    #
    # @param primary_xml [String] Path to the primary.xml.gz file
    # @param name [String] Name of the repository
    def add_rpmmd_repo(primary_xml, name)
      repo = pool.add_repo(name)
      File.open(primary_xml) do |gz|
        fd = Solv.xfopen_fd(primary_xml, gz.fileno)
        repo.add_rpmmd(fd, nil, 0)
      end
      pool.createwhatprovides
    end

    attr_reader :pool

  private

    # detect the system architecture
    # @return [String] the machine architecture, equivalent to "uname -m"
    def arch
      # get the machine architecture name ("uname -m")
      arch = Etc.uname[:machine]
      log.info "Detected system architecture: #{arch}"

      # use "armv7hl" packages on "armv7l" (bsc#1183795)
      if arch == "armv7l"
        arch = "armv7hl"
        log.info "Using #{arch} package architecture"
      end

      arch
    end
  end
end
