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
require "y2packager/self_update_addon_repo"

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
        textdomain "packager"

        if !init_installation_repositories
          Yast::Popup.Error(
            _("Failed to initialize the software repositories.\nAborting the installation.")
          )
          return :abort
        end

        if products.empty?
          Yast::Popup.Error(
            _("Unable to find base products to install.\nAborting the installation.")
          )
          return :abort
        end

        adjust_base_product_selection
        :next
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

        # add extra addon repo built from the initial self update repository (bsc#1101016)
        Y2Packager::SelfUpdateAddonRepo.create_repo if Y2Packager::SelfUpdateAddonRepo.present?

        true
      end

      # Adjust product selection
      #
      # During installation, all products are selected by default. So if there
      # is more than 1, we should unselect them all. The user will select one
      # later.
      #
      # On the other hand, if only one product is available, we should make
      # sure that it is selected for installation because, during upgrade, it
      # is not automatically selected.
      #
      # @see https://github.com/yast/yast-packager/blob/7e1a0bbb90823b03c15d92f408036a560dca8aa3/src/modules/Packages.rb#L1876
      # @see https://github.com/yast/yast-packager/blob/fbc396df910e297915f9f785fc460e72e30d1948/src/modules/Packages.rb#L1905
      def adjust_base_product_selection
        forced_base_product = Y2Packager::Product.forced_base_product

        if forced_base_product
          log.info("control.xml wants to force the #{forced_base_product.name} product")

          forced_base_product.select
          discarded_products = products.reject { |p| p == forced_base_product }

          log.info("Ignoring the other products: #{discarded_products.inspect}")
        elsif products.size == 1
          products.first.select
        else
          products.each(&:restore)
        end
      end

      # Return base available products
      #
      # @return [Array<Y2Product>] Available base products
      def products
        @products ||= Y2Packager::Product.available_base_products
      end
    end
  end
end
