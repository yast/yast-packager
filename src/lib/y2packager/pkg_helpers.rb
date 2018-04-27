# encoding: utf-8

# Copyright (c) [2018] SUSE LLC
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

require "yast"
Yast.import "Pkg"

module Y2Packager
  module PkgHelpers
    # Temporary module to add variables support (like $releasever)to some common
    # Yast::Pkg functions
    #
    # This module must be replaced by proper support to handle expanded URLs
    # in Yast::Pkg in the near future.
    #
    # @example Probing a repository
    #   Yast::Pkg.repository_probe(url, "/") #=> URL
    #

    # Augment repository_probe expanding the given URL
    #
    # @param url [String] Repository URL
    # @param pth [String] Product directory
    # @see Yast::Pkg.RepositoryProbe
    def self.repository_probe(url, pth)
      Yast::Pkg.RepositoryProbe(expand_url(url), pth)
    end

    # Expand a URL and add alias_name/name
    #
    # @param url [String] URL to be expanded
    # @return [String]
    def self.expand_url(url, alias_name: "", name: "")
      # FIXME: avoid potential egg-chicken problem if included from AddOnProduct module
      Yast.import "AddOnProduct"
      Yast::AddOnProduct.SetRepoUrlAlias(Yast::Pkg.ExpandedUrl(url), alias_name, name)
    end

    # Augment SourceCreate expanding the URL
    #
    # @param url [String] Repository URL
    # @param pth [String] Product directory
    # @return [Integer,nil] Source ID for the registered repository;
    #   nil or -1 when it could not be created.
    # @see Yast::Pkg.SourceCreate
    def self.source_create(url, pth = "", alias_name: nil, name: nil)
      alias_name ||= ""
      name ||= ""
      # Expanding URL in order to "translate" tags like $releasever
      expanded_url = expand_url(url, alias_name: alias_name, name: name)
      src_id = Yast::Pkg.SourceCreate(expanded_url, pth)
      Yast::Pkg.SourceChangeUrl(src_id, url) if src_id && src_id != -1
      src_id
    end

    # Augment SourceCreateType expanding the URL
    #
    # @param url [String] Repository URL
    # @param pth [String] Product directory
    # @param type [String] Repository type
    # @return [Integer,nil] Source ID for the registered repository;
    #   nil or -1 when it could not be created.
    # @see Yast::Pkg.SourceCreateType
    def self.source_create_type(url, pth, type, alias_name: nil, name: nil)
      alias_name ||= ""
      name ||= ""
      # Expanding URL in order to "translate" tags like $releasever
      expanded_url = expand_url(url, alias_name: alias_name, name: name)
      src_id = Yast::Pkg.SourceCreateType(expanded_url, pth, type)
      Yast::Pkg.SourceChangeUrl(src_id, url) if src_id && src_id != -1
      src_id
    end

    # Augment RepositoryAdd expanding the base URL
    #
    # @param repo [Hash] Repository specification
    # @return [Integer,nil] Source ID for the registered repository;
    #   nil or -1 when it could not be created.
    # @see Yast::Pkg.RepositoryAdd
    def self.repository_add(repo)
      new_repo = Yast.deep_copy(repo)
      new_repo["base_urls"] = new_repo["base_urls"].map { |u| expand_url(u) }
      Yast::Pkg.RepositoryAdd(new_repo)
    end
  end
end
