# ------------------------------------------------------------------------------
# Copyright (c) 2019 SUSE LLC, All Rights Reserved.
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
  # This class scans the installation medium type and detects which installation
  # medium type it is (online/offline/standard).
  class MediumType
    class << self
      include Yast::Logger

      # Type of the installation medium, raises an exception if the installation
      # URL is not set (nil) or is empty.
      #
      # @return [Symbol] Symbol describing the medium, one of `:offline`,
      # `:online` or `:standard`
      def type
        @type ||= detect_medium_type
      end

      # Is the medium an online installation medium? (SLE Online)
      # Raises an exception if the installation URL is not set (nil) or is empty.
      # The online installation medium contains no repository
      # or a repository without any base product.
      def online?
        type == :online
      end

      # Is the medium an offline installation medium?  (SLE Offline)
      # Raises an exception if the installation URL is not set (nil) or is empty.
      # The offline installation medium contains several installation repositories.
      # (At least one base product and one module/extension, usually there are
      # several base products and many modules/extensions.)
      def offline?
        type == :offline
      end

      # Is the medium an standard installation medium? (openSUSE Leap)
      # Raises an exception if the installation URL is not set (nil) or is empty.
      # The standard installation medium contains a single repository
      # with at least one base product. (Usually there is only one base product.)
      def standard?
        type == :standard
      end

    private

      #
      # Detect the medium type.
      #
      # @return [Symbol] Symbol describing the medium, one of `:offline`,
      # `:online` or `:standard`
      def detect_medium_type
        url = Yast::InstURL.installInf2Url("")

        raise "The installation URL is not set" if url.nil? || url.empty?

        # scan the number of the products in the media.1/products file
        downloader = Y2Packager::RepomdDownloader.new(url)
        product_repos = downloader.product_repos

        # the online medium should not contain any repository
        # TODO: how to detect an invalid installation URL or a broken medium??
        if product_repos.empty?
          log.info("Detected medium type: online (no repository on the medium)")
          return :online
        end

        # the offline medium contains several modules and extensions
        if product_repos.size > 1
          log.info("Detected medium type: offline (found #{product_repos.size} product repos)")
          return :offline
        end

        # no preferred base product for evaluating the dependencies
        base_product = nil
        # run the scan even when there is only one repository on the medium
        force_scan = true
        base_products = Y2Packager::ProductLocation.scan(url, base_product, force_scan)
          .select { |p| p.details&.base }

        if base_products.empty?
          log.info("Detected medium type: online (no base product found on the medium)")
          :online
        else
          log.info("Detected medium type: standard (found #{base_products.size} base products)")
          :standard
        end
      end
    end
  end
end
