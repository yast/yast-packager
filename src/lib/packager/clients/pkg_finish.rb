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

    REPOS_DIR = "/etc/zypp/repos.d"
    SCHEMES_TO_DISABLE = [:cd, :dvd]

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

    def modes
      [:installation, :update, :autoinst]
    end

    def title
      _("Saving the software manager configuration...")
    end

    def write
      #     File "/openSUSE-release.prod" is no more on the media
      #     but directly in the RPM. Don't create the directory
      #     and don't copy the file manually anymore.
      #
      #     (since evrsion 2.17.5)
      #
      #     // Copy information about product (bnc#385868)
      #     // FIXME: this is a temporary hack containing a hardcoded file name
      #     string media_prod = Pkg::SourceProvideOptionalFile (
      # 	Packages::theSources[0]:0, 1,
      # 	"/openSUSE-release.prod");
      #     if (media_prod != nil)
      #     {
      # 	WFM::Execute (.local.bash, sformat ("test -d %1%2 || mkdir %1%2",
      # 						Installation::destdir, "/etc/zypp/products.d"));
      # 	WFM::Execute (.local.bash, sformat ("test -d %3%2 && /bin/cp %1 %3%2",
      # 						media_prod, "/etc/zypp/products.d", Installation::destdir));
      #     }

      # Remove (backup) all sources not used during the update
      # BNC #556469: Backup and remove all the old repositories before any Pkg::SourceSaveAll call
      BackUpAllTargetSources() if Stage.initial && Mode.update

      # See bnc #384827, #381360
      if Mode.update
        Builtins.y2milestone("Adding default repositories")
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
        Builtins.sformat(
          "test -f %1 && /bin/cp -a %1 '%2%1'",
          "/var/lib/YaST2/failed_packages",
          String.Quote(Installation.destdir)
          )
        )
    end

  private

    # During upgrade, old sources are reinitialized
    # either as enabled or disabled.
    # The old sources from targed should go away.
    def BackUpAllTargetSources
      Yast.import "Directory"

      if !FileUtils.Exists(REPOS_DIR)
        Builtins.y2error("Directory %1 doesn't exist!", REPOS_DIR)
        return
      end

      current_repos = Convert.convert(
        SCR.Read(path(".target.dir"), REPOS_DIR),
        :from => "any",
        :to   => "list <string>"
      )

      if current_repos == nil || Builtins.size(current_repos) == 0
        Builtins.y2warning(
          "There are currently no repos in %1 conf dir",
          REPOS_DIR
        )
        return
      else
        Builtins.y2milestone(
          "These repos currently exist on a target: %1",
          current_repos
        )
      end

      cmd = Convert.to_map(
        WFM.Execute(path(".local.bash_output"), "date +%Y%m%d-%H%M%S")
      )
      a_name_list = Builtins.splitstring(
        Ops.get_string(cmd, "stdout", "the_latest"),
        "\n"
      )
      archive_name = Ops.add(
        Ops.add("repos_", Ops.get(a_name_list, 0, "")),
        ".tgz"
      )

      shellcommand = Builtins.sformat(
        "mkdir -p '%1' && cd '%1' && /bin/tar -czf '%2' '%3'",
        String.Quote(Ops.add(Directory.vardir, "/repos.d_backup/")),
        String.Quote(archive_name),
        String.Quote(REPOS_DIR)
      )

      cmd = Convert.to_map(
        SCR.Execute(path(".target.bash_output"), shellcommand)
      )

      if Ops.get_integer(cmd, "exit", -1) != 0
        Builtins.y2error(
          "Unable to backup current repos; Command >%1< returned: %2",
          shellcommand,
          cmd
        )
      end

      success = nil

      Builtins.foreach(current_repos) do |one_repo|
        one_repo = Ops.add(Ops.add(REPOS_DIR, "/"), one_repo)
        Builtins.y2milestone("Removing target repository %1", one_repo)
        success = Convert.to_boolean(
          SCR.Execute(path(".target.remove"), one_repo)
        )
        Builtins.y2error("Cannot remove %1 file", one_repo) if success != true
      end

      Builtins.y2milestone("All old repositories were removed from the target")

      # reload the target to sync the removed repositories with libzypp repomanager
      Pkg.TargetFinish
      Pkg.TargetInitialize("/mnt")

      nil
    end

    def disable_local_repos
      local_repos, other_repos = *::Packages::Repository.all.partition do |repo|
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
