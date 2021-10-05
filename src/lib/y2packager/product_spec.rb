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

require "y2packager/product_spec_reader"

module Y2Packager
  # Describes a product that the user can select for installation
  #
  # The installer allows selecting different products for installation. The list of products can be
  # read from different places (the libzypp database, the control.xml file, etc.). This class
  # represents those products, read from different places.
  #
  # Bear in mind that, once selected, the product is mapped to a proper Y2Packager::Product class,
  # backed by libzypp.
  class ProductSpec
    # @return [String] Name. It corresponds to the libzypp resolvable.
    attr_reader :name

    # @return [String] Name to display to the user
    attr_reader :display_name
    alias_method :label, :display_name

    # @return [String] Version
    attr_reader :version

    # @return [String,nil] Product description
    attr_reader :description

    # @return [String] Architecture
    attr_reader :arch

    # @return [String] License URL
    attr_reader :license_url

    # @return [String] Registration target name used for registering the product.
    attr_reader :register_target

    # @return [Integer] Order in which the product is shown
    attr_reader :order

    # @return [Array<String>,nil] The product dependencies, includes also the transitive
    #  (indirect) dependencies, if the dependencies cannot be evaluated
    #  (e.g. because of conflicts) then the value is `nil`
    attr_reader :depends_on

    # @return [Boolean] Base product flag (true if this is a base product)
    attr_reader :base

    # @return [String] Path on the medium (relative to the medium root)
    attr_reader :dir

    attr_reader :media_name

    class << self
      def base_products
        Y2Packager::ProductSpecReader.new.products.select(&:base)
      end
    end

    # Constructor
    # @param name [String] product name (the identifier, e.g. "SLES")
    # @param version [String] version ("15.2")
    # @param arch [String] The architecture ("x86_64")
    # @param display_name [String] The user visible name ("SUSE Linux Enterprise Server 15 SP2")
    # @param license_url [String] License URL
    # @param register_target [String] The registration target name used
    #   for registering the product, the $arch variable is replaced
    #   by the current machine architecture
    def initialize(name:, version:, arch:, display_name:, license_url: nil, register_target: nil,
                   order: 1, depends_on: nil, base: true, media_name: nil, dir: nil,
                   description: nil)
      @name = name
      @version = version
      @arch = arch
      @display_name = display_name
      @license_url = license_url
      @register_target = register_target
      @order = order
      @depends_on = depends_on
      @base = base
      @media_name = media_name
      @dir = dir
      @description = description
    end
  end
end
