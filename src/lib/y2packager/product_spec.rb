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
  # backed by libzypp when available. The {ControlProductSpec} is an exception to this rule.
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

    # @return [Boolean] Determine whether it is a base product
    attr_reader :base

    # @return [String] Registration target name used for registering the product
    attr_reader :register_target

    class << self
      # Returns the specs for the base products
      #
      # The found product specs are cached. Set the +reload+ param to +true+
      # to force reading them again.
      #
      # @param force [Boolean] Force reloading the list of products
      # @return [Array<Y2Packager::ProductSpec>] List of product specs
      # @see Y2Packager::ProductSpecReader
      def base_products(force: false)
        return @products if @products && !force

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
        @forced_base_product = nil
      end

      # Returns, if any, the base product which must be selected
      #
      # A base product can be forced to be selected through the `select_product`
      # element in the software section of the control.xml file (bsc#1124590,
      # bsc#1143943).
      #
      # @return [Y2Packager::Product, nil] the forced base product or nil when
      # either, it wasn't selected or the selected wasn't found among the
      # available ones.
      def forced_base_product
        return @forced_base_product if @forced_base_product

        Yast.import "ProductFeatures"

        forced_product_name = Yast::ProductFeatures.GetStringFeature("software", "select_product")
        return if forced_product_name.to_s.empty?

        @forced_base_product = base_products.find { |p| p.name == forced_product_name }
      end
    end

    # Constructor
    # @param name [String] product name (the identifier, e.g. "SLES")
    # @param version [String] version ("15.2")
    # @param arch [String] The architecture ("x86_64")
    # @param display_name [String] The user visible name ("SUSE Linux Enterprise Server 15 SP2")
    def initialize(name:, version:, arch:, display_name:, order: 1, base: true, register_target: "")
      @name = name
      @version = version
      @arch = arch
      @display_name = display_name
      @order = order
      @base = base
      @selected = false

      @register_target = register_target
      # expand the "$arch" placeholder
      @register_target = @register_target.gsub("$arch", arch.to_s) if arch
    end

    def selected?
      @selected
    end

    # Marks the product as selected for installation
    #
    # The subclasses are supposed to redefine this method is some additional
    # steps are needed (like setting up a repository or selecting the libzypp
    # package).
    def select
      @selected = true
    end

    # Returns the libzypp based product
    #
    # @return [Y2Packager::Product] Corresponding libzypp product
    def to_product
      @to_product ||= Y2Packager::Product.all.find { |p| p.name == name }
    end
  end
end
