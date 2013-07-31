# encoding: utf-8

# Module:	inst_media.ycp
#
# Authors:	Arvin Schnell <arvin@suse.de>
#
# Purpose:	Show some stuff about the installation media.
#
# $Id$
#
module Yast
  class InstMediaClient < Client
    def main
      Yast.import "Pkg"
      textdomain "packager"

      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "Wizard"
      Yast.import "Packages"
      Yast.import "String"


      @source_list = []

      @num = Builtins.size(Packages.theSources)
      if Ops.less_or_equal(@num, 0)
        Builtins.y2error("Invalid repository")
      else
        Builtins.foreach(Packages.theSources) do |i|
          new_product = Pkg.SourceProductData(i)
          @source_list = Builtins.add(
            @source_list,
            Item(Id(i), Ops.get_locale(new_product, "label", _("Unknown")))
          )
        end
      end


      # screen title
      @title = _("Installation Media")

      # label for showing repositories
      @label = _("Registered Repositories")

      # help text for dialog to show repositories
      @help_text = _("<p>All registered repositories are shown here.\n</p>\n")

      @contents = VBox(
        HCenter(
          HSquash(
            VBox(
              HSpacing(40), # force minimum width
              Left(Label(@label)),
              Table(
                Id(:sources),
                # table header
                Header(_("Name")),
                @source_list
              )
            )
          )
        ),
        VSpacing(2)
      )


      Wizard.OpenAcceptDialog
      Wizard.SetContents(
        @title,
        @contents,
        @help_text,
        Convert.to_boolean(WFM.Args(0)),
        Convert.to_boolean(WFM.Args(1))
      )

      @ret = nil

      while true
        @ret = Wizard.UserInput

        break if @ret == :abort && Popup.ConfirmAbort(:painless)

        break if @ret == :cancel || @ret == :back || @ret == :next
      end

      Wizard.CloseDialog

      deep_copy(@ret)
    end
  end
end

Yast::InstMediaClient.new.main
