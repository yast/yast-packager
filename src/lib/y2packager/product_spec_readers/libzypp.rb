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

require "y2packager/product"
require "y2packager/libzypp_product_spec"

module Y2Packager
  module ProductSpecReaders
    # Reads product specifications from the control file
    class Libzypp
      def products
        Y2Packager::Product.available_base_products.map do |prod|
          Y2Packager::LibzyppProductSpec.new(
            name:         prod.name,
            display_name: prod.display_name,
            version:      prod.version,
            arch:         prod.arch&.to_sym, # TODO: use a symbol (?)
            base:         true,
            order:        prod.order
          )
        end
      end
    end
  end
end
