# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# ------------------------------------------------------------------------------

require "yast"
require "y2packager/product"

Yast.import "Packages"
Yast.import "PackageCallbacks"
Yast.import "Popup"

module Y2Packager
  module Clients
    # Client to initialize software repositories
    #
    # It is intended to be used before the inst_complex_welcome client.
    # If more than one product is available in the installation media, unselects
    # all of them (the user should set a product later).
    #
    # @see adjust_base_product_selection
    class InstRepositoriesInitialization
      include Yast::Logger
      include Yast::I18n

      # Client main method
      def main
        textdomain "installation"

        if init_installation_repositories
          adjust_base_product_selection
          :next
        else
          Yast::Popup.Message(
            _("Failed to initialize the software repositories.\nAborting the installation.")
          )
          :abort
        end
      end

    private

      # Initialize installation repositories
      def init_installation_repositories
        Yast::PackageCallbacks.RegisterEmptyProgressCallbacks
        Yast::Packages.InitializeCatalogs
        return false if Yast::Packages.InitFailed
        Yast::Packages.InitializeAddOnProducts

        # bnc#886608: Adjusting product name (for &product; macro) right after we
        # initialize libzypp and get the base product name (intentionally not translated)
        # FIXME: UI.SetProductName(Product.name || "SUSE Linux")
        Yast::PackageCallbacks.RestorePreviousProgressCallbacks
        true
      end

      # Adjust product selection
      #
      # All products are selected by default. So if there is more than 1, we should unselect
      # them all. The user will select one later.
      #
      # See https://github.com/yast/yast-packager/blob/7e1a0bbb90823b03c15d92f408036a560dca8aa3/src/modules/Packages.rb#L1876
      def adjust_base_product_selection
        products = Y2Packager::Product.available_base_products
        products.each(&:restore) if products.size > 1
      end
    end
  end
end
