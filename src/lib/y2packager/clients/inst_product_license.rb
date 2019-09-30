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

require "yast"
require "y2packager/dialogs/inst_product_license"
require "y2packager/medium_type"
require "y2packager/product"
require "y2packager/product_control_product"
Yast.import "Language"
Yast.import "GetInstArgs"
Yast.import "Mode"

module Y2Packager
  module Clients
    # This client shows a license confirmation dialog for the base selected product
    #
    # The client will be skipped (returning `:auto` or `:next`) in these
    # situations:
    #
    # * There is no license available for the selected base product.
    # * Running AutoYaST but the license has been already confirmed.
    # * Running a normal installation but there is only 1 base product
    #   (not a multi-product media at all). In that case, the license is
    #   supposed to has been already confirmed in the welcome screen.
    class InstProductLicense
      include Yast::I18n
      include Yast::Logger

      def main
        textdomain "installation"

        if Yast::Mode.auto
          return :next if !available_license? || license_confirmed?
        else
          return :auto unless available_license? && multi_product_media?
        end

        Yast::Wizard.EnableAbortButton
        disable_buttons = Yast::GetInstArgs.enable_back ? [] : [:back]
        Y2Packager::Dialogs::InstProductLicense.new(product,
          disable_buttons: disable_buttons).run
      end

    private

      # Return the selected base product
      #
      # @return [Y2Packager::Product]
      # @see Y2Packager::Product.selected_base
      def product
        return @product if @product

        @product = if Y2Packager::MediumType.online?
          # in an online installation read the products from the control.xml
          Y2Packager::ProductControlProduct.selected
        else
          # otherwise read the product from the medium
          Y2Packager::Product.selected_base
        end

        log.warn "No base product is selected for installation" unless @product
        @product
      end

      # Determines whether a multi-product media is being used
      #
      # This client only makes sense when using a multi-product media.
      #
      # @return [Boolean]
      def multi_product_media?
        if Y2Packager::MediumType.online?
          # in an online installation read the products from the control.xml
          Y2Packager::ProductControlProduct.products.size > 1
        elsif Y2Packager::MediumType.offline?
          # the offline medium always contains several products, but they are
          # in separate sub-repositories so we cannot see them in libzypp
          true
        else
          # otherwise read the products from the medium
          Y2Packager::Product.available_base_products.size > 1
        end
      end

      # Determine whether the product's license should be shown
      #
      # @return [Boolean] true if the license is available; false otherwise.
      def available_license?
        return true if product&.license?

        log.warn "No license for product '#{product.label}' was found" if product
        false
      end

      # Determine whether the product's license has been already confirmed
      #
      # @return [Boolean] true if the license was confirmed; false otherwise.
      def license_confirmed?
        product&.license_confirmed?
      end
    end
  end
end
