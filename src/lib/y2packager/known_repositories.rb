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

require "yaml"
require "yast"

module Y2Packager
  # Track the known repositories from which the system packages (drivers)
  # have been installed (or suggested to the user).
  # @see https://github.com/yast/yast-packager/wiki/Selecting-the-Driver-Packages
  class KnownRepositories
    include Yast::Logger

    STATUS_FILE = "/var/lib/YaST2/system_packages_repos.yaml".freeze

    # Constructor
    def initialize
      Yast.import "Pkg"
      Yast.import "Installation"
    end

    def repositories
      @repositories ||= read_repositories
    end

    def write
      log.info("Writing known repositories #{repositories.inspect} to #{status_file}")

      # accessible only for the root user, the repository URLs should not contain
      # any passwords but rather be safe than sorry
      File.open(status_file, "w", 0o600) do |f|
        f.write(repositories.to_yaml)
      end
    end

    def update
      # add the current repositories
      repositories.concat(current_repositories)
      # remove duplicates and sort them
      repositories.uniq!
      repositories.sort!
    end

    #
    # Return new (unknown) repositories
    #
    # @return [Array<String>] List of new repositories (URLs)
    #
    def new_repositories
      log.info "current repositories: #{current_repositories.inspect}"
      log.info "known repositories: #{repositories.inspect}"

      new_repos = current_repositories - repositories
      log.info "New repositories: #{new_repos.inspect}"
      new_repos
    end

  private

    def read_repositories
      if !File.exist?(status_file)
        log.info("Status file #{status_file} not found")
        return []
      end

      status = YAML.load_file(status_file)
      # unify the file in case it was manually modified
      status.uniq!
      status.sort!

      log.info("Read known repositories from #{status_file}: #{status}")
      status
    end

    def current_repositories
      # only the enabled repositories
      repo_ids = Yast::Pkg.SourceGetCurrent(true)

      urls = repo_ids.map { |r| Yast::Pkg.SourceGeneralData(r)["url"] }
      urls.uniq!
      urls.sort
    end

    def status_file
      # add the current target prefix
      File.join(Yast::Installation.destdir, STATUS_FILE)
    end
  end
end
