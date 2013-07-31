# encoding: utf-8

# File:	clients/inst_desktop.ycp
# Package:	Installation
# Summary:	Desktop Selection
# Authors:	Jiri Srain <jsrain@suse.cz>
#
# $Id$
#
module Yast
  class InstDesktopClient < Client
    def main
      Yast.import "UI"

      textdomain "packager"

      Yast.import "Directory"
      Yast.import "GetInstArgs"
      Yast.import "Label"
      Yast.import "Packages"
      Yast.import "Popup"
      Yast.import "ProductFeatures"
      Yast.import "Stage"
      Yast.import "Wizard"
      Yast.import "DefaultDesktop"

      # do not offer the dialog if base selection is fixed
      if ProductFeatures.GetFeature("software", "selection_type") == :fixed
        return :auto
      end

      @alt_desktop = DefaultDesktop.Desktop
      @other_desktop = nil

      if @alt_desktop == nil
        DefaultDesktop.Init
        @alt_desktop = DefaultDesktop.Desktop
      end
      if @alt_desktop != nil
        if @alt_desktop != "kde" && @alt_desktop != "gnome"
          @alt_desktop = "other"
        end
      end

      @display = UI.GetDisplayInfo
      @space = Ops.get_boolean(@display, "TextMode", true) ? 1 : 3

      # all the arguments
      @argmap = GetInstArgs.argmap



      @gnome_blurb =
        # explanation text for GNOME
        _(
          "GNOME is a powerful and intuitive desktop\n" +
            "environment that uses Evolution as mailer,\n" +
            "Firefox as browser, and Nautilus as file manager.\n"
        )

      @kde_blurb =
        # explanation text for KDE
        _(
          "KDE is a powerful and intuitive desktop\n" +
            "environment that uses Kontact as mailer,\n" +
            "Dolphin as file manager, and offers\n" +
            "both Firefox and Konqueror as Web browsers.\n"
        )

      # help text 1/3
      @help = _(
        "<p>Both <b>KDE</b> and <b>GNOME</b> are powerful and intuitive\n" +
          "desktop environments. They combine ease of use\n" +
          "and attractive graphical interfaces with their\n" +
          "own sets of perfectly integrated applications.</p>"
      ) +
        # help text 2/3
        _(
          "<p>Choosing the default <b>GNOME</b> or <b>KDE</b> desktop\n" +
            "environment installs a broad set of the\n" +
            "most important desktop applications on your\n" +
            "system.</p>"
        ) +
        # help text 3/3
        _(
          "<p>Choose <b>Other</b> then select from\n" +
            "an alternative, such as a text-only system or a minimal graphical\n" +
            "system with a basic window manager.</p>"
        )

      @kde = VBox(
        Left(
          RadioButton(
            Id("kde"),
            Opt(:notify, :boldFont),
            # radio button
            _("&KDE"),
            @alt_desktop == "kde"
          )
        ),
        Left(
          HBox(
            HSpacing(3),
            Top(Label(@kde_blurb)),
            HSpacing(1),
            Right(
              Top(
                Image(
                  Ops.add(Directory.icondir, "/48x48/apps/yast-kde.png"),
                  ""
                )
              )
            )
          )
        )
      )

      @gnome = VBox(
        Left(
          RadioButton(
            Id("gnome"),
            Opt(:notify, :boldFont),
            # radio button
            _("&GNOME"),
            @alt_desktop == "gnome"
          )
        ),
        HBox(
          HSpacing(3),
          Top(Label(@gnome_blurb)),
          HSpacing(1),
          Right(
            Top(
              Image(
                Ops.add(Directory.icondir, "/48x48/apps/yast-gnome.png"),
                ""
              )
            )
          )
        )
      )

      @contents = RadioButtonGroup(
        Id(:desktop),
        HBox(
          HWeight(1, Empty()), # Distribute excess space 1:2 (left:right)
          VBox(
            VStretch(),
            # label (in bold font)
            VWeight(10, @gnome),
            VSpacing(0.4),
            VWeight(10, @kde),
            VSpacing(0.4),
            VWeight(
              10,
              HBox(
                Left(
                  RadioButton(
                    Id("other"),
                    Opt(:notify, :boldFont),
                    # radio button
                    _("&Other"),
                    @alt_desktop != "gnome" && @alt_desktop != "kde" &&
                      @alt_desktop != nil
                  )
                ),
                HBox(
                  HSpacing(2),
                  # push button
                  RadioButtonGroup(
                    Id(:other_rb),
                    ReplacePoint(Id(:other_options), VBox(VSpacing(4)))
                  )
                )
              )
            ),
            VStretch()
          ),
          HWeight(2, Empty())
        )
      )

      # dialog caption
      Wizard.SetContents(
        _("Desktop Selection"),
        @contents,
        @help,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next
      )
      Wizard.SetTitleIcon("yast-desktop-select")
      Wizard.SetFocusToNextButton

      # initialize other desktop when going back
      if @alt_desktop == "other"
        @other_desktop = DefaultDesktop.Desktop
        EnableOtherOptions()
      end

      @ret = nil
      begin
        @event = UI.WaitForEvent
        @ret = Ops.get(@event, "ID")

        # by default, nothing is selected, enabling next
        # handling [Next] button
        if @ret == "gnome" || @ret == "kde" || @ret == "min_x11" ||
            @ret == "text"
          Wizard.EnableNextButton
        elsif @ret == "other" &&
            (@other_desktop == "min_x11" || @other_desktop == "text")
          Wizard.EnableNextButton
        else
          Wizard.DisableNextButton
        end

        if @ret == :next
          if @alt_desktop == nil || @alt_desktop == ""
            Popup.Message(
              _("No desktop was selected. Select the\ndesktop to install.")
            )
            @ret = nil 
            # alt_desktop is also neither 'nil' nor ""
          elsif @alt_desktop == "other"
            @alt_desktop = @other_desktop
          end
        elsif @ret == :abort
          if Popup.ConfirmAbort(Stage.initial ? :painless : :incomplete)
            return :abort
          end
          next
        elsif @ret == "other"
          EnableOtherOptions()
        elsif @ret == "gnome" || @ret == "kde"
          @alt_desktop = Builtins.tostring(@ret)
          DisableOtherOptions()
        elsif @ret == "min_x11" || @ret == "text"
          @alt_desktop = "other"
          @other_desktop = Builtins.tostring(@ret)
        end
      end until @ret == :back || @ret == :next

      Wizard.EnableNextButton

      @ret = :next if @ret == :accept

      if @ret == :next
        if DefaultDesktop.Desktop != @alt_desktop
          Builtins.y2milestone("Setting default desktop to %1", @alt_desktop)
          DefaultDesktop.SetDesktop(@alt_desktop)
          Packages.ForceFullRepropose
          Packages.Reset([:product])
        end
      end

      Convert.to_symbol(@ret) 



      # EOF
    end

    def EnableOtherOptions
      UI.ReplaceWidget(
        Id(:other_options),
        VBox(
          VSpacing(2),
          Left(
            RadioButton(
              Id("min_x11"),
              Opt(:notify),
              # radio button
              _("&Minimal Graphical System"),
              @other_desktop == "min_x11"
            )
          ),
          Left(
            RadioButton(
              Id("text"),
              Opt(:notify),
              # radio button
              _("&Text Mode"),
              @other_desktop == "text"
            )
          )
        )
      )

      nil
    end

    def DisableOtherOptions
      UI.ReplaceWidget(Id(:other_options), VBox(VSpacing(4)))

      nil
    end
  end
end

Yast::InstDesktopClient.new.main
