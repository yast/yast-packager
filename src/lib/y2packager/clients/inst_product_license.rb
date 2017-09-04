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

module Y2Packager
  module Clients
    # This client shows a license confirmation dialog for the base selected product
    class InstProductLicense
      include Yast::I18n
      include Yast::Logger

      def main
        textdomain "installation"
        return :auto unless available_license?
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
        return true if product && product.license?
        log.warn "No base product is selected for installation" unless product
        if product && !product.license?
          log.warn "No license for product '#{product.label}' was found"
        end
        false
      end
    end
  end
end
