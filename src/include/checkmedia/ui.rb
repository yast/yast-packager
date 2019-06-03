require "shellwords"

# encoding: utf-8
module Yast
  # All user interface functions.
  module CheckmediaUiInclude
    def initialize_checkmedia_ui(_include_target)
      Yast.import "Pkg"
      Yast.import "UI"

      textdomain "packager"

      Yast.import "Wizard"
      Yast.import "CheckMedia"

      Yast.import "Popup"
      Yast.import "Label"
      Yast.import "Sequencer"
      Yast.import "String"
      Yast.import "Stage"
      Yast.import "PackageSystem"
      Yast.import "GetInstArgs"
      Yast.import "Directory"

      # selected input file (used when checking a file instead of physical CD/DVD medium)
      @iso_filename = ""

      # checking file (ISO image) instead of a medium is in progress
      @checking_file = false

      @log_content = ""
    end

    def CDdevices(preferred)
      cds = Convert.convert(
        SCR.Read(path(".probe.cdrom")),
        from: "any",
        to:   "list <map>"
      )
      ret = []

      Builtins.foreach(cds) do |cd|
        dev = Ops.get_string(cd, "dev_name", "")
        model = Ops.get_string(cd, "model", "")
        deflt = preferred == dev
        if !dev.nil? && dev != "" && !model.nil?
          ret = Builtins.add(
            ret,
            Item(Id(dev), Ops.add(model, Builtins.sformat(" (%1)", dev)), deflt)
          )
        end
      end if !cds.nil?

      deep_copy(ret)
    end

    def SetButtonState(running)
      UI.ChangeWidget(Id(:stop), :Enabled, running)
      UI.ChangeWidget(Id(:progress), :Enabled, running)
      UI.ChangeWidget(Id(:next), :Enabled, !running)
      UI.ChangeWidget(Id(:start), :Enabled, !running)
      UI.ChangeWidget(Id(:back), :Enabled, !running)

      nil
    end

    def TranslateInfo(info)
      info = deep_copy(info)
      ret = []

      Builtins.foreach(info) do |i|
        parts = Builtins.splitstring(i, ":")
        key = String.CutBlanks(Ops.get(parts, 0, ""))
        val = String.CutBlanks(Ops.get(parts, 1, ""))
        trasmap = {
          # rich text message, %1 = CD identification
          "app"        => Ops.add(
            Ops.add(
              Ops.add("<P><IMG SRC=\"icon://22/yast-checkmedia\">&nbsp;&nbsp;&nbsp;",
              _("<BIG><B>%1</B></BIG>")
            ),
            @checking_file ? Builtins.sformat("  (%1)", @iso_filename) : ""
          ),
          # rich text message, %1 medium number, e.g. CD1,CD2...
          "media"      => _(
            "<UL><LI>Medium: %1</LI></UL>"
          ),
          # rich text message, %1 = size of the medium
          "size"       => _(
            "<UL><LI>Size: %1</LI></UL>"
          ),
          # rich text message, %1 = result of the check
          "check"      => _(
            "<UL><LI>Result: %1</LI></UL>"
          ),
          # rich text -  error message
          "not an iso" => "<FONT COLOR=red>" +
            _(
              "The drive does not contain a medium or the ISO file system is broken."
            ) + "</FONT>"
        }
        if key == "check"
          # try to translate result string
          # correct MD5
          if val == "md5sum ok"
            # result of the check - success
            val = "<FONT COLOR=\"darkGreen\">" +
              _("<B>OK</B> -- The medium has been successfully verified.") + "</FONT>"
          elsif val == "md5sum wrong"
            # wrong MD5
            val = "<FONT COLOR=red>" +
              _(
                "<B>Error</B> -- MD5 sum does not match<BR>This medium should not be used."
              ) + "</FONT>"
          elsif val == "md5sum not checked"
            # the correct MD5 is unknown
            val = _(
              "<B>Unknown</B> -- The correct MD5 sum of the medium is unknown."
            )
          # progress output
          elsif Builtins.issubstring(val, "%\b\b\b\b")
            key = ""
            Builtins.y2milestone(
              "Ignoring progress output: %1",
              Builtins.mergestring(Builtins.splitstring(val, "\b"), "\\b")
            )
          end
        # don't print MD5 sum (it doesn't help user)
        elsif key == "md5"
          Builtins.y2milestone("Expected MD5 of the medium: %1", val)
          key = ""
        end
        newstr = Ops.get(trasmap, key, "")
        if !newstr.nil? && newstr != ""
          newstr = Builtins.sformat(newstr, val)

          ret = Builtins.add(ret, newstr)
        end
      end if !info.nil?

      Builtins.y2milestone("Translated info: %1", ret)

      deep_copy(ret)
    end

    # does the medium contain MD5 checksum in the application area?
    def md5sumTagPresent(input)
      command = "/usr/bin/dd if=#{input.shellescape} bs=1 skip=33651 count=512"

      res = SCR.Execute(path(".target.bash_output"), command)

      if Ops.get_integer(res, "exit", -1).nonzero?
        Builtins.y2warning("command failed: %1", command)
        return nil
      end

      Builtins.y2milestone(
        "Read application area: %1",
        Ops.get_string(res, "stdout", "")
      )

      Builtins.regexpmatch(Ops.get_string(res, "stdout", ""), "md5sum=")
    end

    # mount CD drive and check whether there is directory 'media.1' (the first medium)
    # and 'boot' (bootable product CD)
    def InsertedCD1
      ret = true
      instmode = Convert.to_string(SCR.Read(path(".etc.install_inf.InstMode")))

      if instmode == "cd" || instmode == "dvd"
        cdrom_device = Convert.to_string(
          SCR.Read(path(".etc.install_inf.Cdrom"))
        )

        # bugzilla #305495
        if cdrom_device.nil? || cdrom_device == ""
          Builtins.y2error("No Cdrom present in install.inf")
          # try to recover
          return true
        end

        # get CD device name
        bootcd = Ops.add("/dev/", cdrom_device)

        # is the device mounted?
        mounts = Convert.convert(
          SCR.Read(path(".proc.mounts")),
          from: "any",
          to:   "list <map>"
        )
        mnt = Builtins.listmap(mounts) do |m|
          { Ops.get_string(m, "spec", "") => Ops.get_string(m, "file", "") }
        end

        dir = ""
        mounted = false

        if Builtins.haskey(mnt, bootcd)
          dir = Ops.get(mnt, bootcd, "")
        else
          dir = Ops.add(
            Convert.to_string(SCR.Read(path(".target.tmpdir"))),
            "/YaST.mnt"
          )
          SCR.Execute(path(".target.mkdir"), dir)
          mounted = Convert.to_boolean(
            SCR.Execute(path(".target.mount"), [bootcd, dir], "-o ro")
          )
        end

        # check for the first medium
        succ = SCR.Execute(
          path(".target.bash"),
          "test -d #{dir.shellescape}/media.1 && test -d #{dir.shellescape}/boot"
        )

        ret = succ.zero?

        # reset to the previous state
        if mounted
          # unmount back
          umnt = Convert.to_boolean(SCR.Execute(path(".target.umount"), dir))
          Builtins.y2milestone("unmounted %1: %2", dir, umnt)
        end
      end

      ret
    end

    def RequireFirstMedium
      until InsertedCD1()
        # warning popup - the CD/DVD drive doesn't contain the first medium (CD1/DVD1)
        if Popup.AnyQuestion(
          Popup.NoHeadline,
          _("Insert the first installation medium."),
          Label.OKButton,
          Label.CancelButton,
          :focus_yes
        ) == false
          break
        end
      end

      nil
    end

    def LogLine(line)
      @log_content = Ops.add(@log_content, line)
      UI.ChangeWidget(Id(:log), :Value, @log_content)
      Builtins.y2debug("content: %1", @log_content)

      nil
    end

    # Main dialog
    # @return [Symbol] Result from UserInput()
    def MainDialog
      req_package = "checkmedia"

      if Ops.less_than(SCR.Read(path(".target.size"), CheckMedia.checkmedia), 0) &&
          !PackageSystem.CheckAndInstallPackagesInteractive([req_package])
        return :abort
      end

      # set wizard buttons at first
      Wizard.SetNextButton(:next, Label.CloseButton) if !CheckMedia.forced_start

      # set buttons according to mode
      if !Stage.initial
        # remove Back button - workflow has only one dialog
        Wizard.HideBackButton
        # remove Abort button - it's useless
        Wizard.HideAbortButton
      end

      # umount CD drives (release all sources)
      if Stage.initial
        # release all media
        Pkg.SourceReleaseAll
      end

      # dialog header
      caption = _("Media Check")

      # help text - media check (header) 1/8
      help = _("<P><B>Media Check</B></P>") +
        # help text - media check 2/8
        _(
          "<P>When you have a problem with\n" \
            "the installation and you are using a CD or DVD installation medium, " \
            "you should check\nwhether the medium is broken.</P>\n"
        ) +
        # help text - media check 3/8
        _(
          "<P>Select a drive, insert a medium into the drive and press <B>Start Check</B>\n" \
            "or use <B>Check ISO File</B> and select an ISO file.\n" \
            "The check can take several minutes depending on speed of the\n" \
            "drive and size of the medium. The check verifies the MD5 checksum.</P> "
        ) +
        # help text - media check 4/8
        _(
          "<P>If the check of the medium fails, you should not continue the installation.\n" \
            "It may fail or you may lose your data. Better replace the broken medium.</P>\n"
        ) +
        # help text - media check 5/8
        _(
          "After the check, insert the next medium and start the procedure again. \n" \
            "The order of the media is irrelevant.\n"
        ) +
        # help text - media check 6/8
        _(
          "<P><B>Note:</B> You cannot change the medium while it is used by the system.</P>"
        ) +
        # help text - media check 7/8
        _(
          "<P>To check media before the installation, " \
            "use the media check item in the boot menu.</P>"
        ) +
        # help text - media check 8/8
        _(
          "<P>If you burn the media yourself, use the <B>pad</B> option in your recording\n" \
            "software. It avoids read errors at the end of the media during the check.</P>\n"
        )

      # advice check of the media
      # for translators: split the message to more lines if needed, use max. 50 characters per line
      label = _(
        "It is recommended to check all installation media\n" \
          "to avoid installation problems. To skip this step press 'Next'"
      )

      contents = VBox(
        # combobox label
        CheckMedia.forced_start ? VBox(Left(Label(label)), VSpacing(0.6)) : Empty(),
        # combo box
        HBox(
          ComboBox(
            Id(:cddevices),
            _("&CD or DVD Drive"),
            CDdevices(CheckMedia.preferred_drive)
          ),
          VBox(
            # empty label for aligning the widgets
            Label(""),
            HBox(
              # push button label
              PushButton(Id(:start), _("&Start Check")),
              PushButton(Id(:eject), _("&Eject"))
            )
          ),
          HStretch()
        ),
        # push button label
        Left(PushButton(Id(:iso_file), _("Check ISO File..."))),
        VSpacing(0.4),
        # widget label
        Left(Label(_("Status Information"))),
        RichText(Id(:log), Opt(:autoScrollDown), ""),
        VSpacing(0.4),
        # progress bar label
        ProgressBar(Id(:progress), _("Progress")),
        VSpacing(0.4),
        # push button label
        PushButton(Id(:stop), Label.CancelButton)
      )

      Wizard.SetContents(
        caption,
        contents,
        help,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next
      )

      ret = nil
      loop do
        # update state of the buttons (enabled/disabled)
        SetButtonState(false)

        ret = Convert.to_symbol(UI.UserInput)

        Builtins.y2milestone("ui: %1", ret)

        if ret == :next || ret == :back
          # avoid reproposing of the installation -  always return `back in
          # the initial mode when the module start wasn't forced (after
          # language selection)
          ret = :back if Stage.initial && !CheckMedia.forced_start
          break
        elsif ret == :cancel
          ret = :abort
          break
        elsif ret == :abort
          if Popup.ConfirmAbort(:painless)
            ret = :abort
            break
          end
        elsif ret == :start || ret == :iso_file
          selecteddrive = ""

          @checking_file = ret == :iso_file

          if @checking_file
            # window title - open file dialog
            selecteddrive = UI.AskForExistingFile(
              @iso_filename,
              "*.iso",
              _("Select an ISO File to Check")
            )

            # remember for the next run
            @iso_filename = selecteddrive if !selecteddrive.nil?
          else
            selecteddrive = Convert.to_string(
              UI.QueryWidget(Id(:cddevices), :Value)
            )
          end

          if !selecteddrive.nil? && selecteddrive != ""
            SetButtonState(true)

            Builtins.y2milestone(
              "starting media check at drive %1",
              selecteddrive
            )

            # try to read one byte from the medium
            res = SCR.Execute(
              path(".target.bash"),
              "/usr/bin/head -c 1 #{selecteddrive.shellescape} > /dev/null"
            )
            if res.nonzero?
              # TRANSLATORS: error message: the medium cannot be read or no medium in the
              # drive; %1 = drive, e.g. /dev/hdc
              LogLine(
                Ops.add(
                  Ops.add(
                    "<FONT COLOR=red>",
                    Builtins.sformat(
                      _("Cannot read medium in drive %1."),
                      selecteddrive
                    )
                  ),
                  "</FONT>"
                )
              )
            else
              if md5sumTagPresent(selecteddrive) == false
                if !Popup.ContinueCancel(
                  _(
                    "The medium does not contain a MD5 checksum.\n" \
                      "The content of the medium cannot be verified.\n" \
                      "\n" \
                      "Only readability of the medium will be checked.\n"
                  )
                )
                  next
                end
              end

              CheckMedia.Start(selecteddrive)

              loop = true
              aborted = false
              while loop
                loop = CheckMedia.Running
                CheckMedia.Process

                progress = CheckMedia.Progress
                data2 = CheckMedia.Info

                if !data2.nil? && Ops.greater_than(Builtins.size(data2), 0)
                  data2 = TranslateInfo(data2)

                  # add new output to the log view
                  info = Builtins.mergestring(data2, "")
                  LogLine(info)
                end

                if Ops.greater_than(progress, 0)
                  UI.ChangeWidget(Id(:progress), :Value, progress)
                end

                ui = Convert.to_symbol(UI.PollInput)

                if ui == :stop || ui == :cancel
                  CheckMedia.Stop
                  loop = false
                  aborted = true
                elsif ui == :abort
                  if Popup.ConfirmAbort(:painless)
                    CheckMedia.Stop

                    return :abort
                  end
                end

                # sleep for a while
                Builtins.sleep(200)
              end

              SetButtonState(false)

              if aborted
                # the check has been canceled
                LogLine(
                  Builtins.sformat(
                    _("<UL><LI>Result: %1</LI></UL>"),
                    _("<B>Canceled</B>")
                  )
                )
              end
            end

            # process remaining output
            CheckMedia.Process
            data = CheckMedia.Info

            if !data.nil? && Ops.greater_than(Builtins.size(data), 0)
              data = TranslateInfo(data)

              # add new output to the log view
              info = Builtins.mergestring(data, "")
              LogLine(info)
            end

            CheckMedia.Release

            # finish the paragraph
            LogLine("<BR></P>")
            # set zero progress
            UI.ChangeWidget(Id(:progress), :Value, 0)
          end
        elsif ret == :eject
          selecteddrive = Convert.to_string(
            UI.QueryWidget(Id(:cddevices), :Value)
          )
          command = "/usr/bin/eject #{selecteddrive.shellescape}"

          Builtins.y2milestone("Executing '%1'", command)

          res = Convert.to_map(
            SCR.Execute(path(".target.bash_output"), command)
          )
          Builtins.y2milestone("Result: %1", res)
        else
          Builtins.y2warning("unknown UserInput: %1", ret)
        end
      end

      if Stage.initial
        # is the first medium in drive?
        RequireFirstMedium()
      end

      ret
    end

    # Main workflow of the idedma configuration
    # @return [Object] Result from WizardSequencer() function
    def MainSequence
      aliases = { "checkmedia" => -> { MainDialog() } }

      sequence = {
        "ws_start"   => "checkmedia",
        "checkmedia" => { abort: :abort, next: :next }
      }

      Wizard.CreateDialog
      Wizard.SetDesktopIcon("org.opensuse.yast.CheckMedia")

      ret = Sequencer.Run(aliases, sequence)

      UI.CloseDialog
      deep_copy(ret)
    end
  end
end
