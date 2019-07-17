# File:  key_manager.ycp
#
# Author:  Ladislav Slezak <lslezak@novell.com>
#
# Purpose:  Manages GPG keys in the package manager
#
# $Id$
module Yast
  # Helpers for creating dialogs
  module PackagerKeyManagerDialogsInclude
    def initialize_packager_key_manager_dialogs(_include_target)
      Yast.import "Pkg"
      Yast.import "UI"

      textdomain "packager"

      Yast.import "Wizard"
      Yast.import "WizardHW"
      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "KeyManager"
      Yast.import "String"
      Yast.import "FileUtils"
      Yast.import "Directory"
      Yast.import "Report"
      Yast.import "Sequencer"

      @gpg_mgr_standalone_mode = false

      # remember the details about the added key from AddGPGKey(),
      # the details are displayed in NewKeySummary()
      @added_key = {}
    end

    # Creates a summary table with GPG key configuration
    # @return [Array] table contents
    def createHWTable
      ret = []

      Builtins.foreach(KeyManager.GetKeys) do |key|
        descr = []
        # escape <> characters in the key name
        # translators: %1 is GPG key name (e.g. 'SuSE Package Signing Key <build@suse.de>')
        descr = Builtins.add(
          descr,
          Builtins.sformat(
            _("Name: %1"),
            String.EscapeTags(Ops.get_string(key, "name", ""))
          )
        )
        # %1 is a GPG Key fingerprint (e.g. '79C179B2E1C820C1890F9994A84EDAE89C800ACA')
        descr = Builtins.add(
          descr,
          Builtins.sformat(
            _("Finger Print: %1"),
            Ops.get_string(key, "fingerprint", "")
          )
        )
        # %1 is the date when the GPG key was generated (e.g. '9.10.2000')
        descr = Builtins.add(
          descr,
          Builtins.sformat(_("Created: %1"), Ops.get_string(key, "created", ""))
        )
        expires = Ops.get_integer(key, "expires_raw", 0)
        exp_str = if Ops.greater_than(expires, 0) && ::Time.now.to_i > expires
          # %1 is the date when the GPG key expired (e.g. '10.6.2005'), display the date in red
          Builtins.sformat(
            _("Expires: <font color = \"red\">%1</font> (The key is expired.)"),
            Ops.get_string(key, "expires", "")
          )

        # summary string - the GPG key never expires
        elsif expires.zero?
          _("The key never expires.")
        else
          # %1 is the date when the GPG key expires (e.g. '21.3.2015') or "Never"
          Builtins.sformat(
            _("Expires: %1"),
            Ops.get_string(key, "expires", "")
          )
        end
        descr = Builtins.add(descr, exp_str)
        icon_tag = "<IMG HEIGHT=\"22\" SRC=\"yast-security\">&nbsp;&nbsp;&nbsp;"
        r = {
          "id"          => Ops.get_string(key, "id", ""),
          "table_descr" => [
            Ops.get_string(key, "id", ""),
            Ops.get_string(key, "name", "")
          ],
          "rich_descr"  => WizardHW.CreateRichTextDescription(
            Ops.add(
              icon_tag,
              Builtins.sformat(_("Key: %1"), Ops.get_string(key, "id", ""))
            ),
            descr
          )
        }
        ret = Builtins.add(ret, r)
      end

      Builtins.y2debug("table content: %1", ret)

      deep_copy(ret)
    end

    # Set/refresh the table content
    def SetItems(selected_key)
      # create description for WizardHW
      items = createHWTable
      Builtins.y2debug("items: %1", items)

      WizardHW.SetContents(items)

      if !selected_key.nil?
        # set the previously selected key
        WizardHW.SetSelectedItem(selected_key)
      end

      # properties of a key cannot be changed, disable Edit button
      UI.ChangeWidget(Id(:edit), :Enabled, false)

      nil
    end

    def refreshNewKeyDetails(file)
      key = {}

      # at first check whether the file exists at all
      if FileUtils.Exists(file)
        # check whether the file contains a valid GPG key
        key = Pkg.CheckGPGKeyFile(file)
        Builtins.y2milestone("File content: %1", key)
      end

      UI.ChangeWidget(Id(:key_id), :Value, Ops.get_string(key, "id", ""))
      UI.ChangeWidget(Id(:key_name), :Value, Ops.get_string(key, "name", ""))
      UI.ChangeWidget(
        Id(:key_fp),
        :Value,
        Ops.get_string(key, "fingerprint", "")
      )
      UI.ChangeWidget(
        Id(:key_creadted),
        :Value,
        Ops.get_string(key, "created", "")
      )
      UI.ChangeWidget(
        Id(:key_expires),
        :Value,
        Ops.get_string(key, "expires", "")
      )

      nil
    end

    # Display a dialog for adding a GPG key
    def AddGPGKey
      contents = VBox(
        Frame(
          Id(:fr),
          _("Select a GPG Key"),
          MarginBox(
            1,
            0.3,
            VBox(
              HBox(
                InputField(Id(:file), Opt(:notify, :hstretch), Label.FileName),
                VBox(Label(""), PushButton(Id(:browse), Label.BrowseButton))
              )
            )
          )
        ),
        VSpacing(1),
        Frame(
          _("Properties of the GPG Key"),
          MarginBox(
            1,
            0.3,
            HBox(
              HSquash(
                VBox(
                  Left(Label(_("Key ID: "))),
                  Left(Label(_("Name: "))),
                  Left(Label(_("Finger Print: "))),
                  Left(Label(_("Created: "))),
                  Left(Label(_("Expires: ")))
                )
              ),
              VBox(
                Label(Id(:key_id), Opt(:hstretch), ""),
                Label(Id(:key_name), Opt(:hstretch), ""),
                Label(Id(:key_fp), Opt(:hstretch), ""),
                Label(Id(:key_creadted), Opt(:hstretch), ""),
                Label(Id(:key_expires), Opt(:hstretch), "")
              )
            )
          )
        )
      )

      # dialog caption
      title = _("Adding a GPG Public Key")

      # help
      help_text = _("<p>\nManage known GPG public keys.</p>\n")

      help_text = Ops.add(
        help_text,
        _(
          "<p>\n" \
            "<b>Adding a New GPG Key</b><br>\n" \
            "To add a new GPG key, specify the path to the key file.\n" \
            "</p>\n"
        )
      )

      Wizard.SetNextButton(:next, Label.OKButton)
      Wizard.SetContents(title, contents, help_text, true, true)

      ret = nil
      begin
        ret = Convert.to_symbol(UI.UserInput)

        Builtins.y2debug("UserInput: %1", ret)

        if ret == :browse
          currentfile = Convert.to_string(UI.QueryWidget(Id(:file), :Value))
          # header in file selection popup
          newfile = UI.AskForExistingFile(
            currentfile,
            "*",
            _("Select a GPG Key To Import")
          )

          if !newfile.nil?
            UI.ChangeWidget(Id(:file), :Value, newfile)
            refreshNewKeyDetails(newfile)
          end
        elsif ret == :file
          keyfile = Convert.to_string(UI.QueryWidget(Id(:file), :Value))

          Builtins.y2debug("The file has changed: %1", keyfile)

          # refresh the information
          refreshNewKeyDetails(keyfile)
        elsif ret == :next
          # validate the entered file
          keyfile = Convert.to_string(UI.QueryWidget(Id(:file), :Value))
          Builtins.y2milestone("Selected file: %1", keyfile)

          if keyfile.nil? || keyfile == ""
            Report.Error(_("Enter a filename"))
            UI.SetFocus(Id(:file))
            ret = :_dummy
            next
          end

          # always add as trusted
          @added_key = KeyManager.ImportFromFile(keyfile, true)

          ret = :_dummy if @added_key.nil? || Builtins.size(@added_key).zero?
        end
      end while !Builtins.contains([:back, :abort, :next], ret)

      Wizard.RestoreNextButton

      ret
    end

    # Display the main dialog for GPG key management
    def KeySummary
      Builtins.y2milestone("Running Summary dialog")

      # dialog caption
      title = _("GPG Public Key Management")

      # help
      help_text = _("<p>\nManage known GPG public keys.</p>\n")

      help_text = Ops.add(
        help_text,
        _(
          "<p>\n" \
            "<b>Adding a New GPG Key</b><br>\n" \
            "To add a new GPG key, use <b>Add</b> and specify the path to the key file.\n" \
            "</p>"
        )
      )

      # help, continued
      help_text = Ops.add(
        help_text,
        _(
          "<p>\n" \
            "<b>Modifying a GPG Key Status</b>\n" \
            "To modify the trusted flag, use <b>Edit</b>. To remove a GPG key, use\n" \
            "<b>Delete</b>.\n" \
            "</p>\n"
        )
      )

      # table header
      WizardHW.CreateHWDialog(title, help_text, [_("Key ID"), _("Name")], [])

      # set the navigation keys according to the current mode
      if @gpg_mgr_standalone_mode
        Wizard.DisableBackButton
        Wizard.SetNextButton(:next, Label.FinishButton)
      else
        Wizard.EnableBackButton
        Wizard.SetNextButton(:next, Label.OKButton)
      end

      ret = nil

      # set the table content
      SetItems(nil)
      begin
        ev = WizardHW.WaitForEvent
        Builtins.y2milestone("WaitForEvent: %1", ev)

        ret = Ops.get_symbol(ev, ["event", "ID"])

        # the selected key
        key_id = Ops.get_string(ev, "selected", "")

        Builtins.y2milestone("Selected key: %1, action: %2", key_id, ret)

        # remove the key
        if ret == :delete
          key = KeyManager.SearchGPGKey(key_id)

          if Popup.YesNo(
            Builtins.sformat(
              _("Really delete key '%1'\n'%2'?"),
              key_id,
              Ops.get_string(key, "name", "")
            )
          )
            KeyManager.DeleteKey(key_id)
            # refresh the table
            SetItems(nil)

            # HACK: - refresh (clear) the rich text part of the dialog
            # TODO: fix a bug in WizardHW?
            SetItems("") if Builtins.size(KeyManager.GetKeys).zero?
          end
        end
      end while !Builtins.contains([:back, :abort, :next, :add], ret)

      ret
    end

    # Run the GPG key management workflow
    def RunGPGKeyMgmt(standalone)
      @gpg_mgr_standalone_mode = standalone

      aliases = { "summary" => -> { KeySummary() }, "add" => [lambda do
        AddGPGKey()
      end, true] }

      sequence = {
        "ws_start" => "summary",
        "summary"  => { abort: :abort, next: :next, add: "add" },
        "add"      => { next: "summary", abort: :abort }
      }

      Builtins.y2milestone(
        "Starting the key management sequence (standalone: %1)",
        standalone
      )
      ret = Sequencer.Run(aliases, sequence)

      ret
    end
  end
end
