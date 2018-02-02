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
require "y2packager/product"
Yast.import "Language"

module Y2Packager
  module Clients
    # This client shows a license confirmation dialog for the base selected product
    #
    # The client will be skipped (returning `:auto`) in these situations:
    #
    # * There is no license available for the selected base product.
    # * There is only 1 base product (not a multi-product media at all).  In
    #   that case, the license is supposed to has been already accepted in the
    #   welcome screen.
    class InstProductLicense
      include Yast::I18n
      include Yast::Logger

      def main
        textdomain "installation"
        return :auto unless multi_product_media? && available_license?
        Y2Packager::Dialogs::InstProductLicense.new(product).run
      end

    private

      # Return the selected base product
      #
      # @return [Y2Packager::Product]
      # @see Y2Packager::Product.selected_base
      def product
        @product ||= Y2Packager::Product.selected_base
      end

      # Determines whether a multi-product media is being used
      #
      # This client only makes sense when using a multi-product media.
      #
      # @return [Boolean]
      def multi_product_media?
        Y2Packager::Product.available_base_products.size > 1
      end

      # Determine whether the product's license should be shown
      #
      # @return [Boolean] true if the license is available; false otherwise.
      def available_license?
        return true if product && product.license?(Yast::Language.language)
        if product.nil?
          log.warn "No base product is selected for installation"
        else
          log.warn "No license for product '#{product.label}' was found"
        end
        false
      end
    end
  end
end
