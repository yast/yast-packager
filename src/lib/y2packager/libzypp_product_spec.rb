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

require "y2packager/product_spec"
require "y2packager/product"

Yast.import "Pkg"
Yast.import "AddOnProduct"

module Y2Packager
  # Describes a product for installation that comes from the libzypp database
  class LibzyppProductSpec < ProductSpec
    def to_product
      @product ||= Y2Packager::Product.available_base_products.find { |p| p.name == name}
    end

    def select
      super

      # reset both YaST and user selection (when going back or any products
      # selected by YaST in the previous steps)
      Yast::Pkg.PkgApplReset
      Yast::Pkg.PkgReset
      to_product.select

      # Reselecting existing add-on-products for installation again
      Yast::AddOnProduct.selected_installation_products.each do |product|
        log.info "Reselecting add-on product #{product} for installation"
        Yast::Pkg.ResolvableInstall(product, :product, "")
      end
    end
  end
end
