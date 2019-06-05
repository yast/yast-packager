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

    # @return [String] Product name (the zypp resolvable)
    attr_reader :product_name
    # @return [String] The product package (*-release RPM usually)
    attr_reader :product_package
    # @return [String] Product summary
    attr_reader :summary
    # @return [String] Product description
    attr_reader :description
    # @return [Integer] Display order
    attr_reader :order
    # @return [Boolean] Base product flag
    attr_reader :base
    # @return [Array<String>] The product dependencies, includes also the transitive
    #  (indirect) dependencies
    attr_reader :depends_on

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

      repomd_files = downloader.download
      return [] if repomd_files.empty?

      repomd_files.each do |repoindex|
        pool.add_rpmmd_repo(repoindex, "/" + repoindex.split("/")[-3])
      end

      finder = Y2Packager::ProductFinder.new(pool)

      # TODO: handle also subdirectories which do not contain any product
      # (custom or 3rd party repositories)
      finder.products(base_product).map do |p|
        media_name_pair = downloader.product_repos.find { |r| r[1] == p[:prod_dir] }
        media_name = media_name_pair ? media_name_pair.first : p[:prod_dir]
        new(media_name, p[:prod_dir],
          product_name: p[:product_name], summary: p[:summary],
          description: p[:description], base: p[:base], order: p[:order],
          depends_on: p[:depends_on], product_package: p[:product_package])
      end
    end

    # Constructor
    #
    # @param name [String] Product name
    # @param dir [String] Location (path starting at the media root)
    def initialize(name, dir, product_name: nil, summary: nil, product_package: nil,
      order: nil, description: nil, base: nil, depends_on: nil)
      @name = name
      @dir = dir

      @product_name = product_name
      @summary = summary
      @description = description
      @order = order
      @base = base
      @depends_on = depends_on
      @product_package = product_package
    end
  end
end
