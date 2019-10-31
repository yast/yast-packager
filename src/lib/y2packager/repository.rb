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

require "uri"
require "y2packager/product"
require "y2packager/resolvable"

module Y2Packager
  # This class represents a libzypp repository
  #
  # It offers a simple API to list them, query basic attributes,
  # find out the products they offer and enabling/disabling them.
  #
  # @example Get all repositories
  #   all_repos = Y2Packager::Repository.all     #=> [#<Y2Packager::Repository>, ...]
  #   enabled = Y2Packager::Repository.enabled   #=> [#<Y2Packager::Repository>]
  #
  # @example Get a repository using a repo ID
  #   repo = Y2Packager::Repository.find(1) #=> #<Y2Packager::Repository>
  #   repo.autorefresh?                   #=> true
  #   repo.url                            #=> "http://download.opensuse.org..."
  #
  # @example Disabling a repository
  #   repo = Y2Packager::Repository.find(1) #=> #<Y2Packager::Repository>
  #   repo.enabled?                       #=> true
  #   repo.disabled!
  #   repo.enabled?                       #=> false
  class Repository
    Yast.import "Pkg"

    # Repository schemes considered local (see #local?)
    # https://github.com/openSUSE/libzypp/blob/a7a038aeda1ad6d9e441e7d3755612aa83320dce/zypp/Url.cc#L458
    LOCAL_SCHEMES = [:cd, :dvd, :dir, :hd, :iso, :file].freeze

    # @return [Fixnum] Repository ID
    attr_reader :repo_id
    # @return [String] Repository name
    attr_reader :name
    # @return [URI::Generic] Repository URL
    attr_reader :url

    attr_writer :enabled
    private :enabled=

    # Repository was not found
    class NotFound < StandardError; end

    class << self
      # Return all registered repositories
      #
      # @return [Array<Repository>] Array containing all repositories
      #
      # @see Yast::Pkg.SourceGetCurrent
      # @see Y2Packager::Repository.find
      def all
        Yast::Pkg.SourceGetCurrent(false).map do |repo_id|
          find(repo_id)
        end
      end

      # Return only enabled repositories
      #
      # @return [Array<Repository>] Array containing enabled repositories
      def enabled
        all.select(&:enabled?)
      end

      # Return only disabled repositories
      #
      # @return [Array<Repository>] Array containing disabled repositories
      def disabled
        all.reject(&:enabled?)
      end

      # Return a repository with the given repo_id
      #
      # @param repo_id [Fixnum] Repository ID
      # @return [Y2Packager::Repository] Repository instance
      #
      # @raise NotFound
      def find(repo_id)
        repo_data = Yast::Pkg.SourceGeneralData(repo_id)
        raise NotFound if repo_data.nil?

        new(repo_id: repo_id, enabled: repo_data["enabled"],
          name: repo_data["name"], autorefresh: repo_data["autorefresh"],
          url: URI(repo_data["url"]))
      end

      # Add a repository
      #
      # @param name        [String]       Name
      # @param enabled     [Boolean]      Is the repository enabled?
      # @param autorefresh [Boolean]      Is auto-refresh enabled for this repository?
      # @param url         [URI::Generic] Repository URL
      # @return [Y2Packager::Repository,nil] New repository or nil if creation failed
      def create(name:, url:, enabled: true, autorefresh: true)
        repo_id = Yast::Pkg.RepositoryAdd(
          "name" => name, "base_urls" => [url], "enabled" => enabled, "autorefresh" => autorefresh
        )
        return nil unless repo_id

        new(repo_id: repo_id, name: name, url: URI(url), enabled: enabled, autorefresh: autorefresh)
      end
    end

    # Constructor
    #
    # @param repo_id     [Fixnum]       Repository ID
    # @param name        [String]       Name
    # @param enabled     [Boolean]      Is the repository enabled?
    # @param autorefresh [Boolean]      Is auto-refresh enabled for this repository?
    # @param url         [URI::Generic] Repository URL
    def initialize(repo_id:, name:, enabled:, autorefresh:, url:)
      @repo_id = repo_id
      @name    = name
      @enabled = enabled
      @autorefresh = autorefresh
      @url = url
    end

    # Return repository scheme
    #
    # The scheme is determined using the URL
    #
    # @return [Symbol,nil] URL scheme
    def scheme
      url.scheme ? url.scheme.to_sym : nil
    end

    # Return products contained in the repository
    #
    # @return [Array<Y2Packager::Product>] Products in the repository
    #
    # @see Yast::Pkg.ResolvableProperties
    # @see Y2Packager::Product
    def products
      return @products unless @products.nil?

      # Filter products from this repository
      candidates = Y2Packager::Resolvable.find(kind: :product).select do |pro|
        pro.source == repo_id
      end

      # Build an array of Y2Packager::Product objects
      @products = candidates.map do |data|
        Y2Packager::Product.new(name: data.name, version: data.version,
          arch: data.arch, category: data.category, vendor: data.vendor)
      end
    end

    # Determine if the repository is local
    #
    # @return [Boolean] true if the repository is considered local; false otherwise
    def local?
      LOCAL_SCHEMES.include?(scheme)
    end

    # Determine if the repository is enabled
    #
    # @return [Boolean] true if repository is enabled; false otherwise
    def enabled?
      @enabled
    end

    # Determine if auto-refresh is enabled for the repository
    #
    # @return [Boolean] true if auto-refresh is enabled; false otherwise
    def autorefresh?
      @autorefresh
    end

    # Return addons in the repository
    #
    # @return [Array<Y2Packager::Product>] Addons in the repository
    #
    # @see #products
    def addons
      products.select { |p| p.category == :addon }
    end

    # Enable the repository
    #
    # The repository status will be stored only in memory. Calling to
    # Yast::Pkg.SourceSaveAll will make it persistent.
    #
    # @see Yast::Pkg.SourceSetEnabled
    # @see Yast::Pkg.SourceSaveAll
    def enable!
      success = Yast::Pkg.SourceSetEnabled(repo_id, true)
      success && self.enabled = true
    end

    # Disable the repository
    #
    # The repository status will be stored only in memory. Calling to
    # Yast::Pkg.SourceSaveAll will make it persistent.
    #
    # @see Yast::Pkg.SourceSetEnabled
    # @see Yast::Pkg.SourceSaveAll
    def disable!
      success = Yast::Pkg.SourceSetEnabled(repo_id, false)
      success && self.enabled = false
    end
  end
end
