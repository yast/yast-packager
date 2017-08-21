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
Yast.import "GetInstArgs"

module Y2Packager
  module Clients
    # This client shows a license confirmation dialog for the base selected product
    class InstProductLicense
      def main
        if !selected_product.license?
          return Yast::GetInstArgs.going_back ? :back : :next
        end

        Y2Packager::Dialogs::InstProductLicense.new(selected_product).run
      end

      def selected_product
        @selected_product ||= Y2Packager::Product.selected_base
      end
    end
  end
end
