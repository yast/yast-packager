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

      # Returns the cached medium type value. If the medium detection has not been
      # called yet (via the `type` method) then it returns `nil`.
      #
      # @see .type
      # @return [Symbol,nil] Symbol describing the medium or `nil`
      def type_value
        @type
      end

      # Possible types for type value
      POSSIBLE_TYPES = [:online, :offline, :standard].freeze

      # Allows to overwrite detected medium type. Useful e.g. when upgrade of
      # registered system with Full medium should act like Online medium.
      # @param type [Symbol] possible values are `:online`, `:offline` and `:standard`
      def type=(type)
        log.info "Overwritting medium to #{type}"

        if !POSSIBLE_TYPES.include?(type)
          raise ArgumentError, "Not allowed MediumType #{type.inspect}"
        end

        @type = type
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

      # Helper method which evaluates the client arguments and the installation
      # medium type and returns whether the client should be skipped.
      #
      # @return [Boolean] True if the client should be skipped.
      #
      def skip_step?
        return false if Yast::WFM.Args.empty?

        skip = Yast::WFM.Args(0) && Yast::WFM.Args(0)["skip"]
        return true if skip&.split(",")&.include?(type.to_s)

        only = Yast::WFM.Args(0) && Yast::WFM.Args(0)["only"]
        return true if only && !only.split(",").include?(type.to_s)

        false
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
