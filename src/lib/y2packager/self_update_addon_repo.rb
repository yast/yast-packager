# Copyright (c) 2018 SUSE LLC
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

require "fileutils"
require "cgi"

require "yast"
require "y2packager/self_update_addon_filter"
require "packages/package_downloader"

Yast.import "Directory"
Yast.import "Pkg"

module Y2Packager
  # create a local add-on repository from a self-update repository
  class SelfUpdateAddonRepo
    extend Yast::Logger

    REPO_PATH = File.join(Yast::Directory.vardir, "self_update_addon").freeze

    #
    # Create an addon repository from the self-update repository
    # containing specific packages. The repository is a plaindir type
    # and does not contain any metadata.
    #
    # @param repo_id [Integer] repo_id repository ID
    # @param path [String] path where to download the packages
    #
    # @return [Boolean] true if a repository has been created,
    #   false when no addon package was found in the self update repository
    #
    def self.copy_packages(repo_id, path = REPO_PATH)
      pkgs = SelfUpdateAddonFilter.packages(repo_id)
      return false if pkgs.empty?

      log.info("Addon packages to download: #{pkgs}")

      ::FileUtils.mkdir_p(path)

      pkgs.each do |pkg|
        downloader = Packages::PackageDownloader.new(repo_id, pkg)
        log.info("Downloading package #{pkg}...")
        downloader.download(File.join(path, "#{pkg}.rpm"))
      end

      log.info("Downloaded packages: #{Dir["#{path}/*"]}")

      true
    end

    #
    # Is a repository present at the path? (It is enough if it is just
    # an empty directory.)
    #
    # @param path [String] path to the repository
    #
    # @return [Boolean] true if a repository was found, false otherwise
    #
    def self.present?(path = REPO_PATH)
      # the directory exists and is not empty
      ret = File.exist?(path) && !Dir.empty?(path)
      log.info("Repository #{path} exists: #{ret}")
      ret
    end

    #
    # Create a repository from a directory, uses "Plaindir" type,
    # the package metadata are not required.
    #
    # @param path [String] path to the repository
    #
    # @return [Boolean] true on success, false if failed
    #
    def self.create_repo(path = REPO_PATH)
      ret = Yast::Pkg.SourceCreateType("dir://#{CGI.escape(path)}?alias=SelfUpdate0",
        "", "Plaindir")
      log.info("Created self update addon repo: #{ret}")
      ret
    end
  end
end
