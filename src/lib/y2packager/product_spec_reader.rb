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
require "y2packager/medium_type"

module Y2Packager
  # Reads product specification from different sources
  class ProductSpecReader
    include Yast::Logger

    # Returns the list of product specifications.
    #
    # @return [Y2Packager::ProductSpec] List of product specifications
    def products
      # products_from_control || products_from_offline || products_from_libzypp

      case Y2Packager::MediumType.type
      when :online
        products_from_control
      when :offline
        products_from_multi_repos
      else
        products_from_libzypp
      end
    end

  private

    # @raise RuntimeError
    def products_from_control
      control_products = Y2Packager::ProductSpecReaders::Control.new.products
      raise "The control file does not define any base product!" if control_products.empty?

      log.info "Products from control file: #{control_products.map(&:name).join(", ")}"
      control_products
    end

    def products_from_multi_repos
      repo_products = Y2Packager::ProductSpecReaders::Full.new.products(
        Yast::InstURL.installInf2Url("")
      )
      log.info "Products from medium: #{repo_products.map(&:name).join(", ")}"
      repo_products
    end

    def products_from_libzypp
      libzypp_products = Y2Packager::ProductSpecReaders::Libzypp.new.products
      log.info "Products from libzypp: #{libzypp_products.map(&:name).join(", ")}"
      libzypp_products
    end
  end
end
