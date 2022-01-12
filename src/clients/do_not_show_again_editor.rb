module Yast
  # Editor for "Do Not Show This Dialog Again" store
  class DoNotShowAgainEditorClient < Client
    def main
      Yast.import "UI"
      Yast.import "DontShowAgain"
      Yast.import "Wizard"
      Yast.import "Label"
      Yast.import "Confirm"

      textdomain "packager"

      @table_index = {}

      # -----------------------------------
      Wizard.CreateDialog
      SetDialogContents()
      @ret = HandleDialog()
      UI.CloseDialog
      # -----------------------------------

      deep_copy(@ret)
    end

    def InitTable
      @table_index = {}

      current_configuration = DontShowAgain.GetCurrentConfigurationMap

      table_items = []
      index_counter = 0

      Builtins.foreach(current_configuration) do |dont_show_type, records|
        # DontShowAgain cannot handle other types, there's no functionality for that
        next if dont_show_type != "inst-source"

        Builtins.foreach(records) do |popup_type, one_record|
          Builtins.foreach(one_record) do |url, record_options|
            # nil records are skipped
            next if record_options.nil?

            index_counter = Ops.add(index_counter, 1)
            table_items = Builtins.add(
              table_items,
              Item(Id(index_counter), dont_show_type, popup_type, url)
            )
            table_index_item = {}
            Ops.set(table_index_item, "q_type", dont_show_type)
            Ops.set(table_index_item, "q_ident", popup_type)
            Ops.set(table_index_item, "q_url", url)
            Ops.set(@table_index, index_counter, table_index_item)
          end
        end
      end

      UI.ChangeWidget(Id(:table), :Items, table_items)

      nil
    end

    def SetDialogContents
      # dialog caption
      caption = _("Editor for 'Do Not Show Again'")

      # help text
      helptext = _(
        "<p>Remove entries by selecting them in the table and clicking the \n" \
        "<b>Delete</b> button. The entries will be removed immediately from \n" \
        "the current configuration.</p>\n"
      )

      contents = VBox(
        Table(
          Id(:table),
          Header(_("Type"), _("Popup Ident."), _("Additional Info")),
          []
        ),
        HBox(
          # FIXME: Add filter
          # `PushButton(`id(`filter), _("&Filter...")),
          # `HSpacing(2),
          PushButton(Id(:delete), _("&Delete"))
        )
      )

      Wizard.SetContentsButtons(
        caption,
        contents,
        helptext,
        Label.BackButton,
        Label.CloseButton
      )
      Wizard.DisableBackButton
      Wizard.DisableAbortButton

      InitTable()

      nil
    end

    def DeleteItem
      delete_item = Convert.to_integer(UI.QueryWidget(Id(:table), :CurrentItem))
      if Confirm.DeleteSelected
        delete_params = Ops.get(@table_index, delete_item)
        DontShowAgain.RemoveShowQuestionAgain(delete_params)
        InitTable()
      end

      nil
    end

    def HandleDialog
      ret = nil

      loop do
        ret = UI.UserInput

        case ret
        when :abort, :cancel, :accept, :next
          abort
        when :delete
          DeleteItem()
        else
          Builtins.y2error("Undefined return %1", ret)
        end
      end

      deep_copy(ret)
    end
  end
end

Yast::DoNotShowAgainEditorClient.new.main
