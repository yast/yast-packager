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

require "yast"
require "y2packager/resolvable"

module Y2Packager
  # Preselect the system packages (drivers) from the specified repositories.
  # @see https://github.com/yast/yast-packager/wiki/Selecting-the-Driver-Packages
  class SystemPackages
    include Yast::Logger

    # @return [Array<String>] Repositories from which the driver packages should be selected
    attr_reader :repositories

    #
    # Constructor
    #
    # @param repository_urls [Array<String>] Repositories from which the driver
    #  packages should be selected
    #
    def initialize(repository_urls)
      log.info "System packages repositories: #{repository_urls.inspect}"
      @repositories = repository_urls
    end

    def packages
      @packages ||= find_packages
    end

    def select
      return if packages.empty?

      log.info "Preselecting system packages: #{packages.inspect}"
      packages.each { |p| Yast::Pkg.PkgInstall(p) }
    end

  private

    #
    # Create repository ID to URL mapping
    #
    # @return [Array<Integer>] List of repository IDs
    #
    def repo_ids(urls)
      all_ids = Yast::Pkg.SourceGetCurrent(true)
      all_ids.select { |i| urls.include?(Yast::Pkg.SourceGeneralData(i)["url"]) }
    end

    def find_packages
      if repositories.empty?
        log.info "No new repository found, not searching system packages"
        return []
      end

      original_solver_flags = Yast::Pkg.GetSolverFlags

      # solver flags for selecting minimal recommended packages (e.g. drivers)
      # see https://github.com/yast/yast-packager/wiki/Selecting-the-Driver-Packages,
      # https://bugzilla.suse.com/show_bug.cgi?id=953522
      Yast::Pkg.SetSolverFlags(
        "ignoreAlreadyRecommended" => false,
        "onlyRequires"             => true
      )
      # select the packages
      Yast::Pkg.PkgSolve(true)

      ids = repo_ids(repositories)

      pkgs = Y2Packager::Resolvable.find(kind:        :package,
                                         transact_by: :solver,
                                         status:      :selected)
      pkgs.select! do |p|
        # the packages from the specified repositories
        ids.include?(p.source)
      end

      # set back the original solver flags
      Yast::Pkg.SetSolverFlags(original_solver_flags)

      pkgs.map!(&:name)
      log.info "Found system packages: #{pkgs}"

      pkgs
    end
  end
end
