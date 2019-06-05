# ------------------------------------------------------------------------------
# Copyright (c) 2019 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require "rexml/document"
require "yast"

Yast.import "Pkg"

module Y2Packager
  # This class downloads the primary.xml metadata file from an rpm-md repository.
  # For multi-product repositories it downloads the files from all product
  # subdirectories.
  class RepomdDownloader
    attr_reader :url, :product_repos

    #
    # Constructor
    #
    # @param url [String] URL of the repository
    #
    def initialize(url)
      @url = url
    end

    #
    # Download the primary.xml file(s) from the repository.
    #
    # @return [Array<String>] List of paths pointing to the downloaded primary.xml files,
    #   returns an empty list if the URL or the repository is not valid.
    #
    def download
      # expand the URL and scan the repositories on the medium
      expanded_url = Yast::Pkg.ExpandedUrl(url)
      @product_repos = Yast::Pkg.RepositoryScan(expanded_url)

      return [] if @product_repos.nil? || @product_repos.empty?

      # add a temporary repository for downloading the files via libzypp
      src = Yast::Pkg.RepositoryAdd("base_urls" => [url])
      product_repos.map do |(_name, dir)|
        # download the repository index file (repomd.xml)
        repomd_file = Yast::Pkg.SourceProvideFile(src, 1, File.join(dir, "repodata/repomd.xml"))

        # parse the index file and get the full name of the primary.xml.gz file
        doc = REXML::Document.new(File.read(repomd_file))
        primary_path = REXML::XPath.first(doc, "//data[@type='primary']/location")
                                   .attribute("href").value

        # download the primary.xml.gz file
        Yast::Pkg.SourceProvideFile(src, 1, File.join(dir, primary_path))
      end
    ensure
      # remove the temporary repository
      Yast::Pkg.SourceDelete(src) if src
    end
  end
end
