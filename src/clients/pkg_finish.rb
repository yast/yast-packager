# encoding: utf-8

# File:
#  pkg_finish.ycp
#
# Module:
#  Step of base installation finish
#
# Authors:
#  Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
module Yast
  class PkgFinishClient < Client
    REPOS_DIR = "/etc/zypp/repos.d"

    def main
      Yast.import "Pkg"

      textdomain "packager"

      Yast.import "Installation"
      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "String"
      Yast.import "FileUtils"
      Yast.import "Packages"

      @ret = nil
      @func = ""
      @param = {}

      # Check arguments
      if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
          Ops.is_string?(WFM.Args(0))
        @func = Convert.to_string(WFM.Args(0))
        if Ops.greater_than(Builtins.size(WFM.Args), 1) &&
            Ops.is_map?(WFM.Args(1))
          @param = Convert.to_map(WFM.Args(1))
        end
      end

      Builtins.y2milestone("starting pkg_finish")
      Builtins.y2debug("func=%1", @func)
      Builtins.y2debug("param=%1", @param)

      if @func == "Info"
        return {
          "steps" => 1,
          # progress step title
          "title" => _(
            "Saving the software manager configuration..."
          ),
          "when"  => [:installation, :update, :autoinst]
        }
      elsif @func == "Write"
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
      else
        Builtins.y2error("unknown function: %1", @func)
        @ret = nil
      end

      Builtins.y2debug("ret=%1", @ret)
      Builtins.y2milestone("pkg_finish finished")
      deep_copy(@ret)
    end

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
  end
end

Yast::PkgFinishClient.new.main
