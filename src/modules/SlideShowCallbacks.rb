require "yast"
require "pathname"

# Yast namespace
module Yast
  # Provides the Callbacks for SlideShow
  class SlideShowCallbacksClass < Module
    include Yast::Logger

    def main
      Yast.import "Pkg"
      Yast.import "UI"

      textdomain "packager"

      Yast.import "Installation"
      Yast.import "Label"
      Yast.import "Mode"
      Yast.import "Stage"
      Yast.import "PackageCallbacks"
      Yast.import "Popup"
      Yast.import "SlideShow"
      Yast.import "PackageSlideShow"
      Yast.import "Message"
      Yast.import "Directory"
      Yast.import "URL"

      @remote_provide = false

      @pkg_inprogress = ""

      # never show the disk space warning popup during autoinstallation
      @ask_again = !Mode.autoinst
      # true == continue with the installation
      @user_input = true
    end

    # Check for user button presses and handle them.
    #
    # @return true if user wishes to abort
    #
    def HandleInput
      button = UI.PollInput

      # in case of cancel ask user if he really wants to quit installation
      if [:abort, :cancel].include?(button)
        if Mode.normal
          SlideShow.SetUserAbort(
            Popup.AnyQuestion(
              Popup.NoHeadline,
              # popup yes-no
              _("Do you really want\nto quit the installation?"),
              Label.YesButton,
              Label.NoButton,
              :focus_no
            )
          )
        elsif Stage.initial
          SlideShow.SetUserAbort(Popup.ConfirmAbort(:unusable)) # Mode::update (), Stage::cont ()
        else
          SlideShow.SetUserAbort(Popup.ConfirmAbort(:incomplete))
        end

        SlideShow.AppendMessageToInstLog(_("Aborted")) if SlideShow.GetUserAbort
      else
        SlideShow.HandleInput(button)
      end

      nil
    end

    # Start of file providal.
    #
    # This can be a download (if the package is provided by a remote
    # repository) or simply accessing a local repo, e.g. on the currently
    # mounted installation media.
    #
    def StartProvide(name, archivesize, remote)
      @pkg_inprogress = name
      @remote_provide = remote

      PackageSlideShow.DownloadStart(name, archivesize) if @remote_provide
      nil
    end

    # Update progress during file providal.
    #
    # This is meant to update a progress bar for the download percent.
    #
    def ProgressProvide(percent)
      PackageSlideShow.DownloadProgress(percent) if @remote_provide
      HandleInput()
      !SlideShow.GetUserAbort
    end

    # Update during package download: Percent, average and current bytes per second.
    #
    # Notice that there is also ProgressProvide for only the percentage value;
    # this callback is meant to update a display of the current data rate and
    # possibly predictions about the remaining time based on the data rate.
    #
    def ProgressDownload(_percent, _bps_avg, _bps_current)
      HandleInput()
      !SlideShow.GetUserAbort
    end

    # End of file providal; used both for success (error == 0) and error (error
    # != 0).
    #
    # If this was a download from a remote repo, this means that the download
    # is now finished.
    #
    def DoneProvide(error, reason, name)
      if @remote_provide
        if error.zero?
          PackageSlideShow.DownloadEnd(name)
        else
          PackageSlideShow.DownloadError(error, reason, name)
        end
        @remote_provide = false
      end
      return "C" if SlideShow.GetUserAbort
      return PackageCallbacks.DoneProvide(error, reason, name) if error.nonzero?

      ""
    end

    # A pre- or post-install/uninstall script is started.
    #
    def ScriptStart(patch_name, patch_version, patch_arch, script_path)
      patch_full_name = PackageCallbacks.FormatPatchName(
        patch_name,
        patch_version,
        patch_arch
      )
      Builtins.y2milestone(
        "ScriptStart: patch:%1, script:%2",
        patch_full_name,
        script_path
      )

      # FIXME: maybe use a DelayedProgressPopup here?

      # reset the progressbar
      if UI.WidgetExists(:progressCurrentPackage)
        # FIXME: This widget does not exist anymore.
        UI.ChangeWidget(:progressCurrentPackage, :Label, patch_full_name)
        UI.ChangeWidget(:progressCurrentPackage, :Value, 0)
      end

      # message in the installation log widget, %1 is a patch name which contains the script
      log_line = Builtins.sformat(_("Starting script %1"), patch_full_name)

      SlideShow.AppendMessageToInstLog(log_line)

      nil
    end

    # Progress during a pre- or post-install/uninstall script.
    #
    # Since there is no way to find out how far the execution of this script
    # has progressed, this is only a "ping" notification, not reporting
    # percents.
    #
    def ScriptProgress(ping, output)
      Builtins.y2milestone("ScriptProgress: ping:%1, output: %2", ping, output)
      # FIXME: maybe use a DelayedProgressPopup here?

      if !output.nil? && output != ""
        # remove the trailing new line character
        if Builtins.substring(output, Ops.subtract(Builtins.size(output), 1), 1) == "\n"
          output = Builtins.substring(
            output,
            0,
            Ops.subtract(Builtins.size(output), 1)
          )
        end

        # add the output to the log widget
        SlideShow.AppendMessageToInstLog(output)
      end

      input = UI.PollInput
      Builtins.y2milestone("input: %1", input)

      ![:abort, :close].include?(input)
    end

    # Error reporting during execution of a pre- or post-install/uninstall script.
    #
    def ScriptProblem(description)
      # display Abort/Retry/Ignore popup
      PackageCallbacks.ScriptProblem(description)
    end

    # A pre- or post-install/uninstall script has finished.
    #
    def ScriptFinish
      Builtins.y2milestone("ScriptFinish")

      nil
    end

    def Message(patch_name, patch_version, patch_arch, message)
      patch_full_name = PackageCallbacks.FormatPatchName(
        patch_name,
        patch_version,
        patch_arch
      )
      Builtins.y2milestone("Message (%1): %2", patch_full_name, message)

      if patch_full_name != ""
        # label, %1 is patch name with version and architecture
        patch_full_name = Builtins.sformat(_("Patch %1\n\n"), patch_full_name)
      end

      Popup.LongMessage(Ops.add(patch_full_name, message))

      nil
    end

    #--------------------------------------------------------------------------
    # slide show

    def YesNoButtonBox
      yes_button = PushButton(Id(:yes), Opt(:key_F10), Label.YesButton)
      no_button = PushButton(
        Id(:no),
        Opt(:default, :key_F9),
        Label.NoButton
      )

      HBox(
        HStretch(),
        HWeight(1, yes_button),
        HSpacing(2),
        HWeight(1, no_button),
        HStretch()
      )
    end

    def YesNoAgainWarning(message)
      return @user_input if !@ask_again

      icon = Empty()

      # show the warning icon if possible
      ui_capabilities = UI.GetDisplayInfo

      if Ops.get_boolean(ui_capabilities, "HasLocalImageSupport", false)
        icon = Image("dialog-warning", "")
      end

      content = MarginBox(
        1.5,
        0.5,
        VBox(
          HBox(
            VCenter(icon),
            HSpacing(1),
            VCenter(Heading(Label.WarningMsg)),
            HStretch()
          ),
          VSpacing(0.2),
          Left(Label(message)),
          VSpacing(0.2),
          Left(CheckBox(Id(:dont_ask), Message.DoNotShowMessageAgain)),
          VSpacing(0.5),
          YesNoButtonBox()
        )
      )

      UI.OpenDialog(Opt(:decorated), content)

      ret = UI.UserInput

      @ask_again = !Convert.to_boolean(UI.QueryWidget(Id(:dont_ask), :Value))

      if !@ask_again
        # remember the user input
        @user_input = ret == :yes
      end

      UI.CloseDialog

      ret == :yes
    end

    # Callback that will be called by the packager for each RPM as it is being installed or deleted.
    # Note: The packager doesn't call this directly - the corresponding wrapper callbacks do
    # and pass the "deleting" flag as appropriate.
    #
    def DisplayStartInstall(pkg_name, pkg_location, pkg_description, pkg_size, deleting)
      PackageSlideShow.PkgInstallStart(
        pkg_name,
        pkg_location,
        pkg_description,
        pkg_size,
        deleting
      )
      HandleInput()

      # warn user about exhausted diskspace during installation (not if deleting packages)
      if !deleting && @ask_again
        pkgdu = Pkg.PkgDU(@pkg_inprogress)

        Builtins.y2debug("PkgDU(%1): %2", @pkg_inprogress, pkgdu)

        if pkgdu.nil?
          # disk usage for each partition is not known
          # assume that all files will be installed into the root directory,
          # this is the current free space (in bytes)
          disk_available = Pkg.TargetAvailable(Installation.destdir)

          Builtins.y2milestone(
            "Available space (%1): %2",
            Installation.destdir,
            disk_available
          )

          if disk_available < 0
            log.debug("Data overflow, too much free space available, skipping the check")
          elsif disk_available < pkg_size
            Builtins.y2warning(
              "Not enough free space in %1: available: %2, required: %3",
              Installation.destdir,
              disk_available,
              pkg_size
            )

            cont = YesNoAgainWarning(
              # yes-no popup
              _(
                "The disk space is nearly exhausted.\nContinue with the installation?"
              )
            )

            SlideShow.SetUserAbort(true) if !cont
          end
        else
          # check each mount point
          Builtins.foreach(pkgdu) do |part, data|
            # disk sizes from libzypp, in KiB!
            _disk_size, used_now, used_future, read_only = *data
            # the size difference, how much the package needs on this partition
            required_space = used_future - used_now

            # skip read-only partitions, the package cannot be installed anyway
            if read_only == 1
              Builtins.y2debug("Skipping read-only partition %1", part)
              next
            end

            # nothing to install on this partition, skip it (bsc#926841)
            if required_space <= 0
              log.debug("Nothing to install at #{part}, skipping")
              next
            end

            target_dir = File.join(Installation.destdir, part)

            # handle missing directories (not existing yet or incorrect metadata),
            # if the directory does not exist then go up, normally it should
            # stop at Installation.destdir (but it will stop at "/" at last)
            until File.exist?(target_dir)
              log.warn("Directory #{target_dir} does not exist")
              target_dir = Pathname.new(target_dir).parent.to_s
              log.info("Checking the parent directory (#{target_dir})")
            end

            disk_available = Pkg.TargetAvailable(target_dir)
            Builtins.y2debug(
              "partition: %1 (%2), available: %3",
              part,
              target_dir,
              disk_available
            )

            if disk_available < 0
              log.debug("Data overflow, too much free space available, skipping the check")
              next
            end

            # we need to convert the size to KiB to compare it with the libzypp size
            if (disk_available / 1024) < required_space
              Builtins.y2warning(
                "Not enough free space in %1 (%2): available: %3, required: %4",
                part,
                target_dir,
                disk_available,
                required_space
              )

              cont = YesNoAgainWarning(
                # warning popup - %1 is directory name (e.g. /boot)
                Builtins.sformat(
                  _(
                    "The disk space in partition %1 is nearly exhausted.\n" \
                    "Continue with the installation?"
                  ),
                  part
                )
              )

              SlideShow.SetUserAbort(true) if !cont

              # don't check the other partitions
              raise Break
            end
          end
        end
      end

      nil
    end

    # Notification that a package starts being installed, updated or removed.
    def StartPackage(name, location, summary, install_size, is_delete)
      PackageCallbacks._package_name = name
      PackageCallbacks._package_size = install_size
      PackageCallbacks._deleting_package = is_delete

      DisplayStartInstall(name, location, summary, install_size, is_delete)

      nil
    end

    # Progress while a package is being installed, updated or removed.
    def ProgressPackage(pkg_percent)
      PackageSlideShow.PkgInstallProgress(pkg_percent)
      HandleInput()

      Builtins.y2milestone("Aborted at %1%%", pkg_percent) if SlideShow.GetUserAbort

      !SlideShow.GetUserAbort
    end

    # Notification that a package is finished being installed, updated or removed.
    #
    # just to override the PackageCallbacks default (which does a 'CloseDialog' :-})
    def DonePackage(error, reason)
      return "I" if SlideShow.GetUserAbort

      ret = ""
      if error.nonzero?
        ret = PackageCallbacks.DonePackage(error, reason)
      # put additional rpm output to the installation log
      elsif !reason.nil? && Ops.greater_than(Builtins.size(reason), 0)
        Builtins.y2milestone("Additional RPM output: %1", reason)
        SlideShow.AppendMessageToInstLog(reason)
      end

      if Builtins.size(ret).zero? ||
          Builtins.tolower(Builtins.substring(ret, 0, 1)) == "i"
        PackageSlideShow.PkgInstallDone(
          PackageCallbacks._package_name,
          PackageCallbacks._package_size,
          PackageCallbacks._deleting_package
        )
      end
      ret
    end

    #  at start of file providal
    def StartDeltaProvide(_name, _archivesize)
      nil
    end

    #  at start of file providal
    def StartDeltaApply(_name)
      nil
    end

    # during file providal
    def ProgressDeltaApply(_percent)
      nil
    end

    #  at end of file providal
    def FinishDeltaProvide
      nil
    end

    def ProblemDeltaDownload(descr)
      # error in installation log, %1 is detail error description
      SlideShow.AppendMessageToInstLog(
        Builtins.sformat(_("Failed to download delta RPM: %1"), descr)
      )

      nil
    end

    def ProblemDeltaApply(descr)
      # error in installation log, %1 is detail error description
      SlideShow.AppendMessageToInstLog(
        Builtins.sformat(_("Failed to apply delta RPM: %1"), descr)
      )

      nil
    end

    # change of repository
    # source: 0 .. n-1
    # media:  1 .. n
    #
    def CallbackSourceChange(source, media)
      PackageCallbacks.SourceChange(source, media) # inform PackageCallbacks about the change

      # display remaining packages
      PackageSlideShow.UpdateTotalProgressText

      nil
    end

    def MediaChange(error_code, error, url, product, current, current_label,
      wanted, wanted_label, double_sided, devices, current_device)
      devices = deep_copy(devices)

      PackageCallbacks.MediaChange(
        error_code,
        error,
        url,
        product,
        current,
        current_label,
        wanted,
        wanted_label,
        double_sided,
        devices,
        current_device
      )
    end

    # Install callbacks for slideshow.
    def InstallSlideShowCallbacks
      Builtins.y2milestone("InstallSlideShowCallbacks")

      Pkg.CallbackStartPackage(
        fun_ref(
          method(:StartPackage),
          "void (string, string, string, integer, boolean)"
        )
      )
      Pkg.CallbackProgressPackage(
        fun_ref(method(:ProgressPackage), "boolean (integer)")
      )
      Pkg.CallbackDonePackage(
        fun_ref(method(:DonePackage), "string (integer, string)")
      )

      Pkg.CallbackStartProvide(
        fun_ref(method(:StartProvide), "void (string, integer, boolean)")
      )
      Pkg.CallbackProgressProvide(
        fun_ref(method(:ProgressProvide), "boolean (integer)")
      )
      Pkg.CallbackDoneProvide(
        fun_ref(method(:DoneProvide), "string (integer, string, string)")
      )
      Pkg.CallbackProgressDownload(
        fun_ref(
          method(:ProgressDownload),
          "boolean (integer, integer, integer)"
        )
      )

      Pkg.CallbackSourceChange(
        fun_ref(method(:CallbackSourceChange), "void (integer, integer)")
      )

      Pkg.CallbackStartDeltaDownload(
        fun_ref(method(:StartDeltaProvide), "void (string, integer)")
      )
      Pkg.CallbackProgressDeltaDownload(
        fun_ref(method(:ProgressProvide), "boolean (integer)")
      )
      Pkg.CallbackProblemDeltaDownload(
        fun_ref(method(:ProblemDeltaDownload), "void (string)")
      )
      Pkg.CallbackFinishDeltaDownload(
        fun_ref(method(:FinishDeltaProvide), "void ()")
      )

      Pkg.CallbackStartDeltaApply(
        fun_ref(method(:StartDeltaApply), "void (string)")
      )
      Pkg.CallbackProgressDeltaApply(
        fun_ref(method(:ProgressDeltaApply), "void (integer)")
      )
      Pkg.CallbackProblemDeltaApply(
        fun_ref(method(:ProblemDeltaApply), "void (string)")
      )
      Pkg.CallbackFinishDeltaApply(
        fun_ref(method(:FinishDeltaProvide), "void ()")
      )

      Pkg.CallbackScriptStart(
        fun_ref(method(:ScriptStart), "void (string, string, string, string)")
      )
      Pkg.CallbackScriptProgress(
        fun_ref(method(:ScriptProgress), "boolean (boolean, string)")
      )
      Pkg.CallbackScriptProblem(
        fun_ref(method(:ScriptProblem), "string (string)")
      )
      Pkg.CallbackScriptFinish(fun_ref(method(:ScriptFinish), "void ()"))

      Pkg.CallbackMessage(
        fun_ref(
          PackageCallbacks.method(:Message),
          "boolean (string, string, string, string)"
        )
      )

      Pkg.CallbackMediaChange(
        fun_ref(
          method(:MediaChange),
          "string (string, string, string, string, integer, string, integer, " \
          "string, boolean, list <string>, integer)"
        )
      )

      nil
    end

    # Remove callbacks for slideshow. Should be in SlideShowCallbacks but
    # that doesn't work at the moment.
    def RemoveSlideShowCallbacks
      Builtins.y2milestone("RemoveSlideShowCallbacks")

      Pkg.CallbackStartPackage(nil)
      Pkg.CallbackProgressPackage(nil)
      Pkg.CallbackDonePackage(nil)

      Pkg.CallbackStartProvide(nil)
      Pkg.CallbackProgressProvide(nil)
      Pkg.CallbackDoneProvide(nil)

      Pkg.CallbackSourceChange(nil)

      Pkg.CallbackStartDeltaDownload(nil)
      Pkg.CallbackProgressDeltaDownload(nil)
      Pkg.CallbackProblemDeltaDownload(nil)
      Pkg.CallbackFinishDeltaDownload(nil)

      Pkg.CallbackStartDeltaApply(nil)
      Pkg.CallbackProgressDeltaApply(nil)
      Pkg.CallbackProblemDeltaApply(nil)
      Pkg.CallbackFinishDeltaApply(nil)

      Pkg.CallbackScriptStart(nil)
      Pkg.CallbackScriptProgress(nil)
      Pkg.CallbackScriptProblem(nil)
      Pkg.CallbackScriptFinish(nil)

      Pkg.CallbackMessage(nil)

      nil
    end

    publish function: :StartProvide, type: "void (string, integer, boolean)"
    publish function: :ProgressProvide, type: "boolean (integer)"
    publish function: :ProgressDownload, type: "boolean (integer, integer, integer)"
    publish function: :DoneProvide, type: "string (integer, string, string)"
    publish function: :ScriptStart, type: "void (string, string, string, string)"
    publish function: :ScriptProgress, type: "boolean (boolean, string)"
    publish function: :ScriptProblem, type: "string (string)"
    publish function: :ScriptFinish, type: "void ()"
    publish function: :Message, type: "void (string, string, string, string)"
    publish function: :DisplayStartInstall, type: "void (string, string, string, integer, boolean)"
    publish function: :StartPackage, type: "void (string, string, string, integer, boolean)"
    publish function: :ProgressPackage, type: "boolean (integer)"
    publish function: :DonePackage, type: "string (integer, string)"
    publish function: :StartDeltaProvide, type: "void (string, integer)"
    publish function: :StartDeltaApply, type: "void (string)"
    publish function: :ProgressDeltaApply, type: "void (integer)"
    publish function: :ProblemDeltaDownload, type: "void (string)"
    publish function: :ProblemDeltaApply, type: "void (string)"
    publish function: :CallbackSourceChange, type: "void (integer, integer)"
    publish function: :MediaChange,
      type:     "string (string, string, string, string, integer, string, integer, " \
                "string, boolean, list <string>, integer)"
    publish function: :InstallSlideShowCallbacks, type: "void ()"
    publish function: :RemoveSlideShowCallbacks, type: "void ()"
  end

  SlideShowCallbacks = SlideShowCallbacksClass.new
  SlideShowCallbacks.main
end
