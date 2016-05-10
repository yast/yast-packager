# encoding: utf-8

# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# ------------------------------------------------------------------------------

require "installation/finish_client"
require "packages/repository"

module Yast
  class PkgFinishClient < ::Installation::FinishClient
    include Yast::I18n
    include Yast::Logger

    # Path to libzypp repositories
    REPOS_DIR = "/etc/zypp/repos.d"
    # Repository schemes to disable (disable_local_repos)
    SCHEMES_TO_DISABLE = [:cd, :dvd]
    # Path to failed_packages file
    FAILED_PACKAGES_PATH = "/var/lib/YaST2/failed_packages"
    # Command to create a tar.gz to back-up old repositories
    TAR_CMD = "mkdir -p '%<source>s' && cd '%<source>s' "\
      "&& /bin/tar -czf '%<archive>s' '%<target>s'"


    # Constructor
    def initialize
      textdomain "packager"

      Yast.import "Pkg"
      Yast.import "Installation"
      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "String"
      Yast.import "FileUtils"
      Yast.import "Packages"
    end

    # @see Implements ::Installation::FinishClient#modes
    def modes
      [:installation, :update, :autoinst]
    end

    # @see Implements ::Installation::FinishClient#title
    def title
      _("Saving the software manager configuration...")
    end

    # @see Implements ::Installation::FinishClient#write
    def write
      # Remove (backup) all sources not used during the update
      # BNC #556469: Backup and remove all the old repositories before any Pkg::SourceSaveAll call
      BackUpAllTargetSources() if Stage.initial && Mode.update

      # See bnc #384827, #381360
      if Mode.update
        log.info("Adding default repositories")
        WFM.call("inst_extrasources")
      end

      disable_local_repos

      # save all repositories and finish target
      Pkg.SourceSaveAll
      Pkg.TargetFinish

      # save repository metadata cache to the installed system
      # (needs to be done _after_ saving repositories, see bnc#700881)
      Pkg.SourceCacheCopyTo(Installation.destdir)

      # copy list of failed packages to installed system
      WFM.Execute(
        path(".local.bash"),
        format("test -f %<path>s && /bin/cp -a %<path>s '%<destdir>s%<path>s'",
          path: FAILED_PACKAGES_PATH, destdir: String.Quote(Installation.destdir)))
    end

  private

    # During upgrade, old sources are reinitialized
    # either as enabled or disabled.
    # The old sources from targed should go away.
    def BackUpAllTargetSources
      Yast.import "Directory"

      if !File.exist?(REPOS_DIR)
        log.error("Directory #{REPOS_DIR} doesn't exist!")
        return
      end

      current_repos = SCR.Read(path(".target.dir"), REPOS_DIR)

      if current_repos.nil? || current_repos.empty?
        log.warn("There are currently no repos in #{REPOS_DIR} conf dir")
        return
      else
        log.info("These repos currently exist on a target: #{current_repos}")
      end

      cmd = WFM.Execute(path(".local.bash_output"), "date +%Y%m%d-%H%M%S")
      a_name_list = (cmd["stdout"] || "the_latest").split("\n")
      archive_name = "repos_#{a_name_list.first}.tgz"

      compress_cmd = format(TAR_CMD,
        source: String.Quote(Ops.add(Directory.vardir, "/repos.d_backup/")),
        archive: String.Quote(archive_name),
        target: String.Quote(REPOS_DIR))
#
      cmd = SCR.Execute(path(".target.bash_output"), compress_cmd)

      if !cmd["exit"].zero?
        log.error("Unable to backup current repos; Command >#{compress_cmd}< returned: #{cmd}")
      end

      current_repos.each do |repo|
        file = File.join(REPOS_DIR, repo)
        log.info("Removing target repository #{file}")
        if !SCR.Execute(path(".target.remove"), file)
          log.error("Cannot remove #{one_repo} file")
        end
      end

      log.info("All old repositories were removed from the target")

      # reload the target to sync the removed repositories with libzypp repomanager
      Pkg.TargetFinish
      Pkg.TargetInitialize("/mnt")

      nil
    end

    # Disable CD/DVD repositories if needed
    #
    # Given a CD/DVD repository 'local_repo':
    # * if all products it contains are available through another repository,
    #   then 'local_repo' is disabled.
    # * if some product contained in 'local_repo' is not available through another
    #   non-CD/DVD repository, then 'local_repo' is left untouched.
    def disable_local_repos
      local_repos, other_repos = *::Packages::Repository.enabled.partition do |repo|
        SCHEMES_TO_DISABLE.include?(repo.scheme)
      end
      product_names = other_repos.map(&:products).flatten.map(&:name)
      local_repos.each do |repo|
        uncovered = repo.products.reject { |p| product_names.include?(p.name) }
        if uncovered.empty?
          log.info("Repo #{repo.repo_id} will be disabled because products are present "\
            "in other repositories")
          repo.disable!
        else
          log.info("Repo #{repo.repo_id} cannot be disabled because these products " \
                   "are not available through other repos: #{uncovered.map(&:name)}")
        end
      end
    end
  end
end
