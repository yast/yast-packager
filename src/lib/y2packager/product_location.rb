# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

module Y2Packager
  # This class represents a product located on a multi-repository medium,
  # libzypp reads the available products from /medium.1/products file.
  class ProductLocation
    # @return [String] Products on the medium
    attr_reader :name
    # @return [String] User selected products
    attr_reader :dir

    # Constructor
    #
    # @param name [String] Product name
    # @param dir [String] Location (path starting at the media root)
    def initialize(name, dir)
      @name = name
      @dir = dir
    end
  end
end
