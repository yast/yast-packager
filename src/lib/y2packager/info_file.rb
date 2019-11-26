# Copyright (c) [2019] SUSE LLC
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

require "digest"

module Y2Packager
  # Small class to hold info files related information
  #
  # It is responsible for reading and generating a unique ID.
  class InfoFile
    class << self
      # Reads a file from the given path
      #
      # @param file_path [String] File path to read
      # @return [InfoFile,nil] InfoFile if it was read or nil if it could not be read
      def read(file_path)
        content = Yast::SCR.Read(Yast::Path.new(".target.string"), file_path)
        return nil unless content

        new(content)
      end
    end

    # @return [String] File content
    attr_reader :content

    # Constructor
    #
    # @param content [String] File content
    def initialize(content)
      @content = content
    end

    # File unique ID
    #
    # The file ID is based on the file content. The path is not taken into account.
    #
    # @return [String]
    def id
      @id ||= Digest::SHA2.hexdigest(content)
    end
  end
end
