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
require "y2packager/product_location_details"

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
    # Scan the URL for the available product subdirectories
    # and their products.
    #
    # @param url [String] The base repository URL
    # @param base_product [String,nil]  The base product used for evaluating the
    #   product dependencies, if nil the solver can select any product to satisfy
    #   the dependencies.
    #
    # @return [Array<Y2Packager::ProductLocation>] The found products
    #
    def self.scan(url, base_product = nil)
      log.info "Scanning #{Yast::URL.HidePassword(url)} for products..."

      downloader = Y2Packager::RepomdDownloader.new(url)
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

      # TODO: handle also subdirectories which do not contain any product
      # (custom or 3rd party repositories)
      finder.products(base_product).map do |p|
        media_name_pair = downloader.product_repos.find { |r| r[1] == p[:prod_dir] }
        media_name = media_name_pair ? media_name_pair.first : p[:prod_dir]

        if p[:product_name]
          details = ProductLocationDetails.new(product: p[:product_name], summary: p[:summary],
            description: p[:description], base: p[:base], order: p[:order],
            depends_on: p[:depends_on], product_package: p[:product_package])
        end

        new(media_name, p[:prod_dir], product: details)
      end
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
  end
end
