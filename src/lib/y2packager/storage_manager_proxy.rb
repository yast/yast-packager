#!/usr/bin/env ruby
#
# encoding: utf-8

# Copyright (c) [2017] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "storage"

module Y2Packager
  # Class to safely access some useful methods usually provided by the instance
  # of Y2Storage::StorageManager. If Y2Storage is available, all the calls will
  # be forwarded to the mentioned object. Otherwise, safe defaults will be
  # provided.
  #
  # This class plays the same role than the storage_wrapper client that existed
  # in the YCP era. Mainly allowing (limited) operation if yast2-storage is not
  # available in order to break the strong dependency cycle.
  class StorageManagerProxy
    include Yast::Logger

    def initialize
      require "y2storage"
      @manager = Y2Storage::StorageManager.instance
    rescue LoadError
      log.info("Y2Storage not available. Fallback values will be used")
      @manager = nil
    end

    # Staging devicegraph at Y2Storage::StorageManager or empty devicegraph if
    # Y2Storage is not available
    #
    # @return [Storage::Devicegraph]
    def staging
      return manager.staging if manager

      log.info("Y2Storage not available. Instantiating an empty devicegraph")
      Storage::Devicegraph.new
    end

    # Revision of the staging devicegraph if Y2Storage is available, 0 otherwise
    #
    # @return [Fixnum]
    def staging_revision
      manager ? manager.staging_revision : 0
    end

  protected

    attr_reader :manager
  end
end
