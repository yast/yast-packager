# Copyright (c) [2021] SUSE LLC
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

require "y2packager/product_spec"

module Y2Packager
  # Describes a product for installation that comes from the XML definition
  #
  # These products are not backed by a libzypp product at the beginning of the
  # installation. The corresponding product should become available as soon as
  # the product is registered.
  class ControlProductSpec < ProductSpec
    # @return [String] License URL
    attr_reader :license_url
    # @return [String] Registration target name used for registering the product
    attr_reader :register_target

    # @param register_target [String] The registration target name used
    #   for registering the product, the $arch variable is replaced
    #   by the current machine architecture
    # @param license_url [String] License URL
    def initialize(name:, version:, arch:, display_name:, order:, license_url:, register_target:)
      super(name: name, version: version, display_name: display_name, arch: arch,
            order: order, base: true)

      # expand the "$arch" placeholder
      @register_target = register_target&.gsub("$arch", arch) || ""
      @license_url = license_url
    end
  end
end
