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
require "packager/cfa/zypp_conf"

module Yast
  class PkgFinishClient < ::Installation::FinishClient
    include Yast::I18n
    include Yast::Logger

    # Path to libzypp repositories
    REPOS_DIR = "/etc/zypp/repos.d"
    # Path to failed_packages file
    FAILED_PKGS_PATH = "/var/lib/YaST2/failed_packages"
    # Command to create a tar.gz to back-up old repositories
    TAR_CMD = "mkdir -p '%<target>s' && cd '%<target>s' "\
      "&& /bin/tar -czf '%<archive>s' '%<source>s'"
    # Format of the timestamp to be used as repositories backup
    BACKUP_TIMESTAMP_FORMAT = "%Y%m%d-%H%M%S"

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
      Yast.import "Directory"
      Yast.import "ProductFeatures"
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
      backup_all_target_sources if Stage.initial && Mode.update

      # See bnc #384827, #381360
      if Mode.update
        log.info("Adding default repositories")
        WFM.call("inst_extrasources")
      end

      # If repositories weren't load during installation (for example, in openSUSE
      # if online repositories were not enabled), resolvables should be loaded now.
      Pkg.SourceLoad
      disable_local_repos

      # save all repositories and finish target
      Pkg.SourceSaveAll
      Pkg.TargetFinish

      # save repository metadata cache to the installed system
      # (needs to be done _after_ saving repositories, see bnc#700881)
      Pkg.SourceCacheCopyTo(Installation.destdir)

      # Patching /etc/zypp/zypp.conf in order not to install
      # recommended packages, doc-packages,...
      # (needed for products like CASP)
      if ProductFeatures.GetBooleanFeature("software", "minimalistic_configuration")
        set_minimalistic_zypp_conf
      end

      # copy list of failed packages to installed system
      if File.exist?(FAILED_PKGS_PATH)
        ::FileUtils.cp(FAILED_PKGS_PATH, File.join(Installation.destdir, FAILED_PKGS_PATH),
          preserve: true)
      end
    end

  private

    # Backup old sources
    #
    # During upgrade, old sources are reinitialized
    # either as enabled or disabled.
    # The old sources from target should go away.
    def backup_all_target_sources
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

      # Backup repos.d
      repos_backup_dir = File.join(Directory.vardir, "repos.d_backup")
      backup_old_sources(REPOS_DIR, repos_backup_dir).nil?

      # Clean old repositories
      remove_old_sources(current_repos)

      # Sync sources
      sync_target_sources

      nil
    end

    # Disable given repositories if needed
    #
    # Given a local repository:
    #
    # * if all products it contains are available through another repository,
    #   then it will be disabled;
    # * if some product contained is not available through another
    #   repository, then it will be left untouched.
    #
    # @return [Array<Packages::Repository>] List of disabled repositories
    def disable_local_repos
      candidates_repos, other_repos = *::Packages::Repository.enabled.partition(&:local?)
      products = other_repos.map(&:products).flatten.uniq
      candidates_repos.each_with_object([]) do |repo, disabled|
        if repo.products.empty?
          log.info("Repo #{repo.repo_id} (#{repo.name}) does not have products; ignored")
          next
        end
        uncovered = repo.products.reject { |p| products.include?(p) }
        if uncovered.empty?
          log.info("Repo #{repo.repo_id} (#{repo.name}) will be disabled because products " \
            "are present in other repositories")
          repo.disable!
          disabled << repo
        else
          log.info("Repo #{repo.repo_id} (#{repo.name}) cannot be disabled because these " \
            "products are not available through other repos: #{uncovered.map(&:name)}")
        end
      end
    end

    # Backup sources
    #
    # @param source [String] Path of sources to backup
    # @param target [String] Directory to store backup
    # @return [String,nil] Name of the backup archive (locate in the given target directory);
    #                      nil if the backup failed
    def backup_old_sources(source, target)
      archive_name = "repos_#{Time.now.strftime(BACKUP_TIMESTAMP_FORMAT)}.tgz"
      compress_cmd = format(TAR_CMD,
        target: String.Quote(target),
        archive: archive_name,
        source: String.Quote(source))
      cmd = SCR.Execute(path(".target.bash_output"), compress_cmd)
      if !cmd["exit"].zero?
        log.error("Unable to backup current repos; Command >#{compress_cmd}< returned: #{cmd}")
        nil
      else
        archive_name
      end
    end

    # Remove old sources
    #
    # @param [Array<String>] List of repositories to remove
    def remove_old_sources(repos)
      repos.each do |repo|
        file = File.join(REPOS_DIR, repo)
        log.info("Removing target repository #{file}")
        if !SCR.Execute(path(".target.remove"), file)
          log.error("Cannot remove #{repo} file")
        end
      end
      log.info("All old repositories were removed from the target")
    end

    # Reload the target to sync the removed repositories with libzypp
    # repomanager
    def sync_target_sources
      Pkg.TargetFinish
      Pkg.TargetInitialize(Installation.destdir)
    end

    # Set libzypp configuration to install the minimal amount of packages
    #
    # @see Yast::Packager::CFA::ZyppConf#set_minimalistic!
    def set_minimalistic_zypp_conf
      config = Packager::CFA::ZyppConf.new
      config.load
      config.set_minimalistic!
      config.save
    end
  end
end
