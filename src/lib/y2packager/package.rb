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
require "yast2/execute"

Yast.import "Pkg"

module Y2Packager
  # This class represents a libzypp package and it offers an API to common operations.
  #
  # The idea is extending this class with new methods when needed.
  class Package
    include Yast::Logger

    # @return [String] Package's name
    attr_reader :name
    # @return [Integer] Id of the repository where the package lives
    attr_reader :repo_id
    # @return [Symbol] Package's status (:installed, :available, etc.).
    attr_reader :status

    class << self
      # Find packages by name
      #
      # @param name [String] Package name
      # @return [Array<Package>] Packages named like `name`
      def find(name)
        props = Yast::Pkg.ResolvableProperties(name, :package, "")
        return nil if props.nil?
        props.map { |i| new(i["name"], i["source"], i["status"]) }
      end
    end

    # Constructor
    #
    # @param name    [String]  Package name
    # @param repo_id [Integer] Repository ID
    # @param status  [Symbol]  Package status (:installed, :available, etc.)
    def initialize(name, repo_id, status)
      @name = name
      @repo_id = repo_id
      @status = status
    end

    # Download a package to the given path
    #
    # @param path [String] Path to download the package to
    # @return [Boolean] true if the package was downloaded
    def download_to(path)
      Yast::Pkg.ProvidePackage(repo_id, name, path)
    end

    # Download and extract the package to the given directory
    #
    # @param path [String] Path to download the package to
    # @return [Boolean] true if the package was extracted
    def extract_to(directory)
      rpm_path = File.join(directory, "#{name}.rpm")
      return false unless download_to(rpm_path)

      Dir.chdir(directory) do
        log.info("Extracting package #{rpm_path} to #{directory}")
        Yast::Execute.locally(
          ["rpm2cpio", rpm_path],
          ["cpio", "--quiet", "--sparse", "-dimu", "--no-absolute-filename"]
        )
      end

      true
    end
  end
end
