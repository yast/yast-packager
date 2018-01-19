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

require "y2packager/clients/inst_product_license"
require "y2packager/product"

Yast.import "Pkg"
Yast.import "Report"
Yast.import "GetInstArgs"

module Y2Packager
  module Clients
    # This client shows a license confirmation dialog for the upgraded base product
    #
    # The client will display an error and return :back if not product is found.
    # If no license is found for the selected product it returns :auto.
    # The license is not displayed when going back in the workflow.
    # @see Y2Packager::Clients::InstProductLicense
    class InstProductUpgradeLicense < InstProductLicense
      def main
        textdomain "installation"

        # do not display the license when going back, skip the dialog
        return :back if Yast::GetInstArgs.going_back

        if !product
          # TRANSLATORS: An error message, the package solver could not find
          # any product to upgrade in the selected partition.
          Yast::Report.Error(_("Error: Cannot find any product to upgrade.\n" \
            "Make sure the selected partition contains an upgradable product."))
          return :back
        end

        return :auto unless available_license?

        log.info "Displaying license for product: #{product.inspect}"

        Y2Packager::Dialogs::InstProductLicense.new(product).run
      end

    private

      # Return the selected base product for upgrade
      #
      # @return [Y2Packager::Product]
      # @see Y2Packager::Product.selected_base
      def product
        return @product if @product

        # temporarily run the update mode to let the solver select the product for upgrade
        # (this will correctly handle possible product renames)
        Yast::Pkg.PkgUpdateAll({})
        @product = Y2Packager::Product.selected_base
        # restore the initial status, the package update will be turned on later again
        Yast::Pkg.PkgReset
        @product
      end
    end
  end
end
