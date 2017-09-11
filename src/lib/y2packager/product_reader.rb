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
require "y2packager/product"
require "y2packager/product_sorter"

Yast.import "Pkg"

module Y2Packager
  # Read the product information from libzypp
  class ProductReader
    include Yast::Logger

    # In installation Read the available libzypp base products for installation
    # @return [Array<Y2Packager::Product>] the found available base products,
    #   the products are sorted by the 'displayorder' provides value
    def available_base_products
      products = available_products

      result = products.map do |prod|
        prod_pkg = product_package(prod["product_package"], prod["source"])

        if prod_pkg
          prod_pkg["deps"].find { |dep| dep["provides"] =~ /\Adisplayorder\(\s*([0-9]+)\s*\)\z/ }
          displayorder = Regexp.last_match[1].to_i if Regexp.last_match
        end

        Y2Packager::Product.new(name: prod["name"], short_name: prod["short_name"],
                                display_name: prod["display_name"], order: displayorder,
                                installation_package: installation_package_mapping[prod["name"]])
      end

      # If no product contains a 'system-installation()' tag but there is only 1 product,
      # we assume that it is the base one.
      if result.size == 1 && installation_package_mapping.empty?
        log.info "Assuming that #{result.inspect} is the base product."
        return result
      end

      # only installable products
      result.select!(&:installation_package)

      # sort the products
      result.sort!(&::Y2Packager::PRODUCT_SORTER)

      log.info "available base products #{result}"

      result
    end

    def product_package(name, repo_id)
      return nil unless name
      Yast::Pkg.ResolvableDependencies(name, :package, "").find do |prod|
        prod["source"] == repo_id
      end
    end

    def release_notes_package_for(product_name)
      provides = Yast::Pkg.PkgQueryProvides("release-notes()")
      release_notes_packages = provides.map(&:first).uniq
      release_notes_packages.find do |name|
        dependencies = Yast::Pkg.ResolvableDependencies(name, :package, "").first["deps"]
        dependencies.any? do |dep|
          dep["provides"].to_s.match(/release-notes\(\)\s*=\s*#{product_name}\s*/)
        end
      end
    end

  private

    # read the available products, remove potential duplicates
    # @return [Array<Hash>] pkg-bindings data structure
    def available_products
      products = Yast::Pkg.ResolvableProperties("", :product, "")

      # remove duplicates, there migth be different flavors ("DVD"/"POOL")
      # or archs (x86_64/i586), when selecting the product to install later
      # libzypp will select the correct arch automatically
      products.uniq! { |prod| prod["name"] }
      log.info "Found products: #{products.map { |prod| prod["name"] }}"

      products
    end

    def installation_package_mapping
      return @installation_package_mapping if @installation_package_mapping
      installation_packages = Yast::Pkg.PkgQueryProvides("system-installation()")
      log.info "Installation packages: #{installation_packages.inspect}"

      @installation_package_mapping = {}
      installation_packages.each do |list|
        pkg_name = list.first
        # There can be more instances of same package in different version. We except that one
        # package provide same product installation. So we just pick the first one.
        dependencies = Yast::Pkg.ResolvableDependencies(pkg_name, :package, "").first["deps"]
        install_provide = dependencies.find do |d|
          d["provides"] && d["provides"].match(/system-installation\(\)/)
        end

        # parse product name from provides. Format of provide is
        # `system-installation() = <product_name>`
        product_name = install_provide["provides"][/system-installation\(\)\s*=\s*(\S+)/, 1]
        log.info "package #{pkg_name} install product #{product_name}"
        @installation_package_mapping[product_name] = pkg_name
      end

      @installation_package_mapping
    end
  end
end
