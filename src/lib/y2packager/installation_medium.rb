# ------------------------------------------------------------------------------
# Copyright (c) 2021 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require "yast"

require "y2packager/product_location"
require "y2packager/repomd_downloader"

Yast.import "InstURL"

module Y2Packager
  # This class represent informations we know about installation medium
  class InstallationMedium
    class << self
      include Yast::Logger

      # Does installation medium contain repository with base product?
      #
      # @return [Boolean]
      def contain_repo?
        read if @repo.nil?

        @repo
      end

      # Does installation medium contain multiple repositories with products?
      #
      # @return [Boolean]
      def contain_multi_repos?
        read if @multi_repo.nil?

        @multi_repo
      end

    private

      # Reads info about medium
      def read
        url = Yast::InstURL.installInf2Url("")

        raise "The installation URL is not set" if url.nil? || url.empty?

        @multi_repo = false
        @repo = true

        # scan the number of the products in the media.1/products file
        downloader = Y2Packager::RepomdDownloader.new(url)
        product_repos = downloader.product_repos

        # the offline medium contains several modules and extensions
        if product_repos.size > 1
          @multi_repo = true
          log.info("Detected multi repository medium (found #{product_repos.size} product repos)")
          return
        end

        # no preferred base product for evaluating the dependencies
        base_product = nil
        # run the scan even when there is only one repository on the medium
        force_scan = true
        base_products = Y2Packager::ProductLocation.scan(url, base_product, force_scan)
          .select { |p| p.details&.base }

        log.info("Base Products: #{base_products.inspect}")

        # TODO: is it correct to decide if medium contain repository
        # based on availability of base product?
        @repo = !base_products.empty?
      end
    end
  end
end
