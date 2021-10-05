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

require "y2packager/product_spec_readers/full"
require "y2packager/product_spec_readers/libzypp"
require "y2packager/product_spec_readers/control"

module Y2Packager
  # Reads product specification from different sources
  #
  # NOTE: at this point, the only source of products specification is the control file.
  class ProductSpecReader
    # Returns the list of product specifications.
    #
    # @return [Y2Packager::ProductSpec] List of product specifications
    def products
      products_from_control || products_from_offline || products_from_libzypp
    end

  private

    def products_from_control
      control_products = Y2Packager::ProductSpecReaders::Control.new.products
      return nil if control_products.empty?

      control_products
    end

    def products_from_offline
      offline_products = Y2Packager::ProductSpecReaders::Full.new.products(
        Yast::InstURL.installInf2Url("")
      )
      return nil if offline_products.empty?

      offline_products
    end

    def products_from_libzypp
      Y2Packager::ProductSpecReaders::Libzypp.new.products
    end
  end
end
