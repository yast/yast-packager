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

require "solv"

module Y2Packager
  # This is a wrapper for the Solv::Pool class
  class SolvablePool
    def initialize
      @pool = Solv::Pool.new
      @pool.setarch
    end

    #
    # Load repository metadata to the pool.
    #
    # @param primary_xml [String] Path to the primary.xml.gz file
    # @param name [String] Name of the repository
    def add_rpmmd_repo(primary_xml, name)
      repo = pool.add_repo(name)
      gz = open(primary_xml)
      fd = Solv.xfopen_fd(primary_xml, gz.fileno)
      repo.add_rpmmd(fd, nil, 0)
      pool.createwhatprovides
    ensure
      gz&.close
    end

    attr_reader :pool
  end
end
