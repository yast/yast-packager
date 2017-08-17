# encoding: utf-8

require "yast"

# Yast namespace
module Yast
  # Show /info.txt (if present) in a popup
  class InstShowInfoClass < Module
    def main
      Yast.import "UI"

      # IMPORTANT: maintainer of yast2-add-on is responsible for this module

      textdomain "packager"

      Yast.import "Report"
      Yast.import "Label"
    end

    # @param [String] info_file (/info.txt" - Copied from inst media to inst-sys by linuxrc)
    def show_info_txt(info_file)
      display_info = UI.GetDisplayInfo
      size_x = Builtins.tointeger(Ops.get_integer(display_info, "Width", 800))
      size_y = Builtins.tointeger(Ops.get_integer(display_info, "Height", 600))
      if Ops.greater_or_equal(size_x, 800) && Ops.greater_or_equal(size_y, 600)
        size_x = 78
        size_y = 18
      else
        size_x = 54
        size_y = 15
      end

      if Ops.less_or_equal(SCR.Read(path(".target.size"), info_file), 0)
        Builtins.y2milestone("No %1", info_file)
        return
      end

      info_text = Convert.to_string(SCR.Read(path(".target.string"), info_file))

      report_settings = Report.Export
      message_settings = Ops.get_map(report_settings, "messages", {})
      timeout_seconds = Ops.get_integer(message_settings, "timeout", 0)
      # timeout_seconds = 12;
      use_timeout = Ops.greater_than(timeout_seconds, 0)
      button_box = HBox(
        HStretch(),
        HWeight(1, PushButton(Id(:ok), Label.OKButton)),
        HStretch()
      )

      if use_timeout
        button_box = Builtins.add(
          button_box,
          HWeight(1, PushButton(Id(:stop), Label.StopButton))
        )
        button_box = Builtins.add(button_box, HStretch())
      end

      UI.OpenDialog(
        VBox(
          MinSize(size_x, size_y, RichText(Opt(:plainText), info_text)),
          if use_timeout
            Label(Id(:timeout), Builtins.sformat("   %1   ", timeout_seconds))
          else
            VSpacing(0.2)
          end,
          button_box,
          VSpacing(0.2)
        )
      )

      UI.SetFocus(:ok)
      button = :nothing
      begin
        button = Convert.to_symbol(
          use_timeout ? UI.TimeoutUserInput(1000) : UI.UserInput
        )

        if button == :timeout
          timeout_seconds = Ops.subtract(timeout_seconds, 1)
          UI.ChangeWidget(
            :timeout,
            :Value,
            Builtins.sformat("%1", timeout_seconds)
          )
        elsif button == :stop
          use_timeout = false
          UI.ChangeWidget(:stop, :Enabled, false)
          UI.ChangeWidget(:timeout, :Value, "")
        end
      end while button != :ok && Ops.greater_than(timeout_seconds, 0)

      UI.CloseDialog

      nil
    end

    publish function: :show_info_txt, type: "void (string)"
  end

  InstShowInfo = InstShowInfoClass.new
  InstShowInfo.main
end
