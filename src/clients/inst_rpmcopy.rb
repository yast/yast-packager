require "y2packager/resolvable"

module Yast
  # Install all the RPM packages the user has selected.
  # Show installation dialogue. Show progress bars.
  # Request medium change from user.
  class InstRpmcopyClient < Client
    def main
      Yast.import "Pkg"
      textdomain "packager"

      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "Installation"
      Yast.import "Language"
      Yast.import "PackageInstallation"
      Yast.import "Packages"
      Yast.import "SlideShow"
      Yast.import "PackageSlideShow"
      Yast.import "SlideShowCallbacks"
      Yast.import "Popup"
      Yast.import "Report"
      Yast.import "SourceManager"
      Yast.import "Linuxrc"
      Yast.import "FileUtils"
      Yast.import "AutoinstData"

      Yast.include self, "packager/storage_include.rb"

      @remaining = []
      @srcremaining = []

      return :auto if Installation.image_only

      # bugzilla #208222
      ReleaseHDDUsedAsInstallationSource()

      # bugzilla #326327
      Packages.SlideShowSetUp(Language.language)

      Pkg.SetTextLocale(Language.language)

      SlideShow.SetLanguage(Language.language)

      # Initialize and check whether some packages need to be installed
      # stop proceeding the script if they don't (Second stage)
      if Stage.cont && !Mode.live_installation && !Mode.autoinst
        InitRemainingPackages()
        if SomePackagesAreRemainForInstallation() != true
          Builtins.y2milestone("No packages need to be installed, skipping...")
          return :auto
        else
          Builtins.y2milestone("Some packages need to be installed...")
        end
      end

      # start target, create new rpmdb if none is existing
      # FIXME error checking is missing all around here, initialization could actually fail!
      if Pkg.TargetInitialize(Installation.destdir) != true
        # continue-cancel popup
        if Popup.ContinueCancel(_("Initializing the target directory failed.")) == false
          return :abort
        end
      end

      if Mode.update
        # Removes all already installed patches and selections.
        # See bugzilla #210552 for more information.
        RemoveObsoleteResolvables()
      end

      if Stage.cont && !Mode.live_installation
        # initialize the package agent in continue mode
        Packages.Init(true)

        # in 1st stage, this is opened already
        SlideShow.OpenDialog
      end

      AutoinstPostPackages() if Mode.autoinst && Stage.cont

      # initial mode, move download area, check for repository caching
      if Stage.initial
        SourceManager.InstInitSourceMoveDownloadArea

        # continue mode, set remaining packages to be installed
      elsif !Mode.live_installation
        InstallRemainingAndBinarySource()
      end

      # Install the software from Medium1 to Mediummax, but not the already
      # installed base packages.
      # This part is also used for installation in running system (Stage::cont ())

      @cdnumbers = CountStartingAndMaxMediaNumber()
      @maxnumbercds = Ops.get(@cdnumbers, "maxnumbercds", 10)
      @current_cd_no = Ops.get(@cdnumbers, "current_cd_no", 1)

      # re-initialize package information
      PackageSlideShow.InitPkgData(true)

      @get_setup = SlideShow.GetSetup
      if @get_setup.nil? || @get_setup == {}
        Builtins.y2milestone("No SlideShow setup has been set, adjusting")
        SlideShow.Setup(
          [
            {
              "name"        => "packages",
              "description" => _("Installing Packages..."),
              "value"       => Ops.divide(
                PackageSlideShow.total_size_to_install,
                1024
              ), # kilobytes
              "units"       => :kb
            }
          ]
        )
      end
      @get_setup = nil

      # Do not open a new SlideShow widget, reuse the old one instead
      @required_to_open_sl_dialog = !SlideShow.HaveSlideWidget

      # BNC #443755
      if @required_to_open_sl_dialog
        Builtins.y2milestone("SlideShow dialog not yet created")
        SlideShow.OpenDialog
      end

      # move the progress to the packages stage
      SlideShow.MoveToStage("packages")

      # (true) : Showing release tab if needed
      SlideShow.RebuildDialog(true)

      # bnc#875350: Log the current user/app_high software selection
      Packages.log_software_selection

      # install packages from CD current_cd_no to CD maxnumbercds
      @result = InstallPackagesFromMedia(@current_cd_no, @maxnumbercds)

      # sync package manager FIXME
      if @result != :abort && !Stage.initial
        @config = {}
        if PackageInstallation.DownloadInAdvance == true
          Ops.set(@config, "download_mode", :download_in_advance)
        end
        Builtins.y2milestone("Calling Pkg::Commit(%1)", @config)
        Pkg.Commit(@config)
      end

      # BNC #443755
      if @required_to_open_sl_dialog
        Builtins.y2milestone("Closing previously opened SlideShow dialog")
        SlideShow.CloseDialog
      end

      if @result != :abort
        if Stage.cont
          # some new SCR asgents might have been installed
          SCR.RegisterNewAgents
        end
      end

      @result
    end

    # Removes all already installed patches and selections.
    # See bugzilla #210552 for more information.
    def RemoveObsoleteResolvables
      Builtins.y2milestone("--------- removing obsolete selections ---------")

      # this removes only information about selections and applied patches
      # it doesn't remove any package
      Builtins.y2milestone(
        "Removing all information about selections and patches in %1",
        Installation.destdir
      )
      Pkg.TargetStoreRemove(Installation.destdir, :selection)

      # disabled by FATE #301990, bugzilla #238488
      # Pkg::TargetStoreRemove (Installation::destdir, `patch);

      Builtins.y2milestone("--------- removing obsolete selections ---------")

      nil
    end

    # Fills-up 'remaining' and 'srcremaining' lists with information of
    # objects that need to be installed.
    def InitRemainingPackages
      Builtins.y2milestone("Looking for remaining packages")

      file_remaining_packages = Ops.add(
        Installation.destdir,
        "/var/lib/YaST2/remaining"
      )
      file_remaining_srcs = Ops.add(
        Installation.destdir,
        "/var/lib/YaST2/srcremaining"
      )

      # Packages remaining for installation
      if FileUtils.Exists(file_remaining_packages)
        @remaining = Convert.convert(
          SCR.Read(path(".target.ycp"), [file_remaining_packages, []]),
          from: "any",
          to:   "list <map <string, any>>"
        )
        @remaining = [] if @remaining.nil?
        Builtins.y2milestone(
          "File %1 contains %2 packages",
          file_remaining_packages,
          Builtins.size(@remaining)
        )
      end

      # repositories remaining for installation
      if FileUtils.Exists(file_remaining_srcs)
        @srcremaining = Convert.convert(
          SCR.Read(path(".target.ycp"), [file_remaining_srcs, []]),
          from: "any",
          to:   "list <string>"
        )
        @srcremaining = [] if @srcremaining.nil?
        Builtins.y2milestone(
          "File %1 contains %2 packages",
          file_remaining_srcs,
          Builtins.size(@srcremaining)
        )
      end

      nil
    end

    # And returns whether some objects need to be installed as the result.
    #
    # @return [Boolean] whether some packages need to be installed
    def SomePackagesAreRemainForInstallation
      # Either 'remaining' or 'srcremaining' are not empty
      size_remaining = @remaining.nil? ? 0 : Builtins.size(@remaining)
      size_srcremaining = @srcremaining.nil? ? 0 : Builtins.size(@srcremaining)

      Builtins.y2milestone(
        "remaining: %1, srcremaining: %2",
        size_remaining,
        size_srcremaining
      )
      Ops.greater_than(size_remaining, 0) ||
        Ops.greater_than(size_srcremaining, 0)
    end

    # Sets remaining packages to be installed
    def InstallRemainingAndBinarySource
      # second stage of package installation, re-read list of remaining binary and source
      # packages

      backupPath = Convert.to_string(
        SCR.Read(
          path(".target.string"),
          [Ops.add(Installation.destdir, "/var/lib/YaST2/backup_path"), ""]
        )
      )
      if !backupPath.nil? && backupPath != ""
        Builtins.y2milestone("create package backups in %1", backupPath)
        Pkg.CreateBackups(true)
        Pkg.SetBackupPath(backupPath)
      end

      failed_packages = 0
      Builtins.y2milestone(
        "%1 resolvables remaining",
        Builtins.size(@remaining)
      )
      Builtins.foreach(@remaining) do |res|
        name = Ops.get_string(res, "name", "")
        kind = Ops.get_symbol(res, "kind", :package)
        arch = Ops.get_string(res, "arch", "")
        vers = Ops.get_string(res, "version", "")
        if !Pkg.ResolvableInstallArchVersion(name, kind, arch, vers)
          failed_packages = Ops.add(failed_packages, 1)
        end
      end

      Builtins.y2milestone(
        "%1 source packages remaining",
        Builtins.size(@srcremaining)
      )
      Builtins.foreach(@srcremaining) do |pkg|
        failed_packages = Ops.add(failed_packages, 1) if !Pkg.PkgSrcInstall(pkg)
      end
      if Ops.greater_than(failed_packages, 0)
        # error report, %1 is number
        Report.Error(
          Builtins.sformat(
            _("Failed to select %1 packages for installation."),
            failed_packages
          )
        )
      end

      nil
    end

    def AutoinstPostPackages
      # post packages from autoinstall
      res = Pkg.DoProvide(AutoinstData.post_packages)
      if Ops.greater_than(
        Builtins.size(res),
        0
      )
        Builtins.foreach(res) do |s, a|
          Builtins.y2warning("Pkg::DoProvide failed for %1: %2", s, a)
        end
      end

      failed = []
      patterns = deep_copy(AutoinstData.post_patterns)
      # set SoftLock to avoid the installation of recommended patterns (#159466)
      Y2Packager::Resolvable.find(kind: :pattern).each do |p|
        Pkg.ResolvableSetSoftLock(p.name, :pattern)
      end
      Builtins.foreach(Builtins.toset(patterns)) do |p|
        failed = Builtins.add(failed, p) if !Pkg.ResolvableInstall(p, :pattern)
      end

      if Ops.greater_than(Builtins.size(failed), 0)
        Builtins.y2error(
          "Error while setting pattern: %1",
          Builtins.mergestring(failed, ",")
        )
        Report.Warning(
          Builtins.sformat(
            _("Could not set patterns: %1."),
            Builtins.mergestring(failed, ",")
          )
        )
      end
      #
      # Solve dependencies
      #
      if !Pkg.PkgSolve(false)
        Report.Error(
          _(
            "The package resolver run failed. Check your software section in the AutoYaST profile."
          )
        )
      end

      nil
    end

    def InstallPackagesFromMedia(current_cd_no, maxnumbercds)
      result = :next

      Builtins.y2milestone(
        "Installing packages from media %1 -> %2",
        current_cd_no,
        maxnumbercds
      )

      # 1->1 for default fist stage installation
      # 0->0 for default second stage (or other) installation
      while Ops.less_or_equal(current_cd_no, maxnumbercds)
        # nothing to install/delete
        if Pkg.IsAnyResolvable(:any, :to_remove) == false &&
            Pkg.IsAnyResolvable(:any, :to_install) == false
          Builtins.y2milestone("No package left for installation")
          break
        end

        # returns [ int successful, list failed, list remaining ]
        config = { "medium_nr" => current_cd_no }
        if PackageInstallation.DownloadInAdvance == true
          Ops.set(config, "download_mode", :download_in_advance)
        end

        Builtins.y2milestone("Commit config: %1", config)

        commit_result = PackageInstallation.Commit(config)

        if commit_result.nil? || Builtins.size(commit_result).zero?
          Builtins.y2error("Commit failed")
          # error message - displayed in a scrollable text area
          # %1 - an error message (details)
          Report.LongError(
            Builtins.sformat(
              _(
                "Installation failed.\n" \
                  "\n" \
                  "Details:\n" \
                  "%1\n" \
                  "\n" \
                  "Package installation will be aborted.\n"
              ),
              Pkg.LastError
            )
          )

          return :abort
        end

        count = Ops.get_integer(commit_result, 0, 0)
        Builtins.y2milestone("%1 packages installed", count)

        failed = Ops.get_list(commit_result, 1, [])
        if Ops.greater_than(Builtins.size(failed), 0)
          Builtins.y2milestone("failed: %1", failed)
          previous_failed = Convert.to_list(
            SCR.Read(
              path(".target.ycp"),
              [
                Ops.add(Installation.destdir, "/var/lib/YaST2/failed_packages"),
                []
              ]
            )
          )
          if Ops.greater_than(Builtins.size(previous_failed), 0)
            failed = Builtins.union(previous_failed, failed)
          end
          SCR.Write(
            path(".target.ycp"),
            Ops.add(Installation.destdir, "/var/lib/YaST2/failed_packages"),
            failed
          )
        end

        remaining = Ops.get_list(commit_result, 2, [])
        if Ops.greater_or_equal(Builtins.size(remaining), 0)
          Builtins.y2milestone("remaining: %1", remaining)
          SCR.Write(
            path(".target.ycp"),
            Ops.add(Installation.destdir, "/var/lib/YaST2/remaining"),
            remaining
          )
        else
          SCR.Execute(
            path(".target.remove"),
            Ops.add(Installation.destdir, "/var/lib/YaST2/remaining")
          )
        end

        srcremaining = Ops.get_list(commit_result, 3, [])
        if Ops.greater_or_equal(Builtins.size(srcremaining), 0)
          Builtins.y2milestone("repository remaining: %1", srcremaining)
          SCR.Write(
            path(".target.ycp"),
            Ops.add(Installation.destdir, "/var/lib/YaST2/srcremaining"),
            srcremaining
          )
        else
          SCR.Execute(
            path(".target.remove"),
            Ops.add(Installation.destdir, "/var/lib/YaST2/srcremaining")
          )
        end

        if Ops.less_than(count, 0) # aborted by user
          result = :abort
          break
        end

        # break on first round with Mediums
        break if Stage.initial && !Mode.test

        current_cd_no = Ops.add(current_cd_no, 1)
      end
      result
    end

    def CountStartingAndMaxMediaNumber
      # Bugzilla #170079
      # Default - unrestricted
      ret = { "maxnumbercds" => 0, "current_cd_no" => 0 }

      # has the inst-sys been successfuly unmounted?
      umount_result = Linuxrc.InstallInf("umount_result")
      media = Linuxrc.InstallInf("InstMode")
      Builtins.y2milestone(
        "umount result: %1, inst repository type: %2",
        umount_result,
        media
      )

      if Packages.metadir_used
        # all is in ramdisk, we can install all repositories now, works in every stage
        Ops.set(ret, "current_cd_no", 0)
        Ops.set(ret, "maxnumbercds", 0)
        Builtins.y2milestone(
          "StartingAndMaxMediaNumber: MetaDir used %1/%2",
          Ops.get(ret, "current_cd_no"),
          Ops.get(ret, "maxnumbercds")
        )
      elsif Stage.initial
        # is CD or DVD medium mounted? (inst-sys)
        if umount_result != "0" && ["cd", "dvd"].include?(media)
          Builtins.y2milestone("The installation CD/DVD cannot be changed.")
          # only the first CD will be installed
          Ops.set(ret, "current_cd_no", 1)
          Ops.set(ret, "maxnumbercds", 1)
        end
        # otherwise use the default setting - install all media
        Builtins.y2milestone(
          "StartingAndMaxMediaNumber: Stage initial %1/%2",
          Ops.get(ret, "current_cd_no"),
          Ops.get(ret, "maxnumbercds")
        )

        # Three following cases have the same solution, CDstart = 0, CDfinish = 0
        # ZYPP should solve what it needs and when.
        # Leaving it here as the backward compatibility if someone decides to change it back.
      elsif Mode.autoinst && Stage.cont &&
          Ops.greater_than(Builtins.size(AutoinstData.post_packages), 0)
        # one more compatibility feature to old YaST, post-packages
        # Simply install a list of package after initial installation (only
        # makes sense with nfs installatons)
        Ops.set(ret, "current_cd_no", 0) # was 1
        Ops.set(ret, "maxnumbercds", 0) # was 10
        Builtins.y2milestone(
          "StartingAndMaxMediaNumber: Autoinst in cont %1/%2",
          Ops.get(ret, "current_cd_no"),
          Ops.get(ret, "maxnumbercds")
        )
      elsif Stage.cont
        # continue with second CD but only in continue mode
        # bug #170079, let zypp solve needed CDs
        Ops.set(ret, "current_cd_no", 0)
        Ops.set(ret, "maxnumbercds", 0)
        Builtins.y2milestone(
          "StartingAndMaxMediaNumber: Stage cont %1/%2",
          Ops.get(ret, "current_cd_no"),
          Ops.get(ret, "maxnumbercds")
        )
      elsif Installation.dirinstall_installing_into_dir
        # All in one
        Ops.set(ret, "current_cd_no", 0) # was 1
        Ops.set(ret, "maxnumbercds", 0) # was 10
        Builtins.y2milestone(
          "StartingAndMaxMediaNumber: Dir install %1/%2",
          Ops.get(ret, "current_cd_no"),
          Ops.get(ret, "maxnumbercds")
        )
      end

      deep_copy(ret)
    end
  end
end

Yast::InstRpmcopyClient.new.main
