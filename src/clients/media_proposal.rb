# encoding: utf-8

# Module:	media_proposal.ycp
#
# Author:	Arvin Schnell <arvin@suse.de>
#
# Purpose:	Initialize the installation media.
#
# $Id$
#
module Yast
  class MediaProposalClient < Client
    def main
      Yast.import "Pkg"
      Yast.import "UI"
      textdomain "packager"

      Yast.import "HTML"
      Yast.import "Mode"
      Yast.import "Language"
      Yast.import "Packages"
      Yast.import "PackageCallbacks"

      Yast.import "Installation"

      @func = Convert.to_string(WFM.Args(0))
      @param = Convert.to_map(WFM.Args(1))
      @ret = {}

      if @func == "MakeProposal"
        @force_reset = Ops.get_boolean(@param, "force_reset", false)
        @language_changed = Ops.get_boolean(@param, "language_changed", false)

        UI.OpenDialog(
          Opt(:decorated),
          # intermediate popup while initializing internal packagemanagement
          Label(_("Reading package information..."))
        )

        Packages.Init(true)

        UI.CloseDialog

        @num = Builtins.size(Packages.theSources)
        if Ops.less_or_equal(@num, 0)
          Builtins.y2error("Invalid repository")
          @ret = {
            "warning"       =>
                               # Proposal for system to update, part of the richtext
                               _("No Valid Installation Media"),
            "warning_level" => :blocker
          }
        else
          @tmp = []

          Builtins.foreach(Packages.theSources) do |i|
            new_product = Pkg.SourceProductData(i)
            @tmp = Builtins.add(@tmp, Ops.get_string(new_product, "label", "?"))
          end

          @ret = { "preformatted_proposal" => HTML.List(@tmp) }
        end
      elsif @func == "AskUser"
        @has_next = Ops.get_boolean(@param, "has_next", false)

        # call some function that displays a user dialog
        # or a sequence of dialogs here:
        #
        # sequence = DummyMod::AskUser( has_next );

        @result = Convert.to_symbol(
          WFM.CallFunction("inst_media", [true, @has_next])
        )

        # Fill return map

        @ret = { "workflow_sequence" => @result }
      elsif @func == "Description"
        # Fill return map.
        #
        # Static values do just nicely here, no need to call a function.

        @ret = {
          # this is a heading
          "rich_text_title" => _("Installation Media"),
          # this is a menu entry
          "menu_title"      => _("&Media"),
          "id"              => "media_stuff"
        }
      end

      deep_copy(@ret)
    end
  end
end

Yast::MediaProposalClient.new.main
