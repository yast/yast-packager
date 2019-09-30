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

require "y2packager/repomd_downloader"
require "y2packager/solvable_pool"
require "y2packager/product_finder"
require "y2packager/resolvable"

Yast.import "URL"

module Y2Packager
  # This class represents a product located on a multi-repository medium,
  # libzypp reads the available products from /medium.1/products file.
  class ProductLocation
    include Yast::Logger

    # @return [String] Product name (user name from the /medium.1/products file)
    attr_reader :name
    # @return [String] Path on the medium (relative to the medium root)
    attr_reader :dir

    # @return [Y2Packager::ProductLocationDetails] Product details
    attr_reader :details

    #
    # Scan the URL for the available product subdirectories and their products.
    # If there is none or only one repository at the URL it returns empty list.
    # Scanning the product details is not needed because there is nothing to
    # select from, that one repository will be used without asking.
    #
    # @param url [String] The base repository URL
    # @param base_product [String,nil]  The base product used for evaluating the
    #   product dependencies, if nil the solver can select any product to satisfy
    #   the dependencies.
    # @param force_scan [Boolean] force evaluating the products (and their
    #   dependencies) even when there is only one repository on the medium.
    #   For the performance reasons the default is `false`, set `true` for
    #   special cases.
    #
    # @return [Array<Y2Packager::ProductLocation>] The found products
    #
    def self.scan(url, base_product = nil, force_scan = false)
      log.info "Scanning #{Yast::URL.HidePassword(url)} for products..."

      downloader = Y2Packager::RepomdDownloader.new(url)
      # Skip the scan if there is none or just one repository, the repository selection
      # is displayed only when there are at least 2 repositories.
      return [] if downloader.product_repos.size < 2 && !force_scan

      pool = Y2Packager::SolvablePool.new

      repomd_files = downloader.primary_xmls
      return [] if repomd_files.empty?

      repomd_files.each do |repomd|
        # Use the directory name as the repository name so we can easily map
        # the found products to their directories on the medium.
        # The repomd path looks like
        #   /var/tmp/.../Module-Basesystem/repodata/*primary.xml.gz
        # so the third component from the end is the repository subdirectory.
        # The directories in the /media.1/products index file start with
        # a slash, add it here as well so we can easily compare that data.
        repo_name = "/" + repomd.split("/")[-3]
        pool.add_rpmmd_repo(repomd, repo_name)
      end

      finder = Y2Packager::ProductFinder.new(pool)

      finder.products(base_product, downloader.product_repos)
    end

    # Constructor
    #
    # @param name [String] Product name
    # @param dir [String] Location (path starting at the media root)
    def initialize(name, dir, product: nil)
      @name = name
      @dir = dir
      @details = product
    end

    # Product summary taken from its details
    #
    # @return [String, nil] nil if there is no details or details does not contain a summary
    def summary
      return nil if !details&.summary || details.summary.empty?

      details.summary
    end

    alias_method :label, :summary

    # Just forward to the details object to easily use the Y2Packager::PRODUCT_SORTER
    # @return [Integer,nil] Product order, `nil` if not defined
    def order
      details&.order
    end

    # Is the product selected to install?
    #
    # @return [Boolean,nil] `true` if the product is selected to install, `false` otherwise,
    #   `nil` if the product name is not set
    def selected?
      return nil unless details

      Y2Packager::Resolvable.any?(kind: :product, name: details.product, status: :selected)
    end
  end
end
