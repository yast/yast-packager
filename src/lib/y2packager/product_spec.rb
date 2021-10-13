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

require "y2packager/product_license_mixin"

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
    include ProductLicenseMixin

    # @return [String] Name. It corresponds to the libzypp resolvable.
    attr_reader :name

    # @return [String] Name to display to the user
    attr_reader :display_name
    alias_method :label, :display_name

    # @return [String] Version
    attr_reader :version

    # @return [String] Architecture
    attr_reader :arch

    # @return [Integer] Order in which the product is shown
    attr_reader :order

    attr_reader :base

    class << self
      # Returns the specs for the base products
      #
      # The found product specs are cached. Set the +reload+ param to +true+
      # to force reading them again.
      #
      # @param reload [Boolean] Force reloading the list of products
      # @return [Array<Y2Packager::ProductSpec>] List of product specs
      # @see Y2Packager::ProductSpecReader
      def base_products(reload: false)
        return @products if @products && !reload

        require "y2packager/product_spec_reader"
        @products = Y2Packager::ProductSpecReader.new.products.select(&:base)
      end

      # Returns the selected base product spec
      #
      # @return [ProductSpec,nil] Returns the select base product spec. It returns nil
      #   if no product is selected.
      def selected_base
        base_products.find(&:selected?)
      end

      # Resets the products cache
      def reset
        @products = nil
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
    def initialize(name:, version:, arch:, display_name:, order: 1, base: true)
      @name = name
      @version = version
      @arch = arch
      @display_name = display_name
      @order = order
      @base = base
      @selected = false
    end

    def selected?
      @selected
    end

    def select
      @selected = true
    end
  end
end
