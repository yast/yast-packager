# encoding: utf-8

# Module:		software_proposal.ycp
#
# Author:		Klaus Kaempf <kkaempf@suse.de>
#
# Purpose:		Proposal function dispatcher - software.
#
#			See also file proposal-API.txt for details.
#
# $Id$
#

require "y2packager/storage_manager_proxy"

module Yast
  class SoftwareProposalClient < Client
    def main
      Yast.import "Pkg"
      textdomain "packager"

      Yast.import "Packages"
      Yast.import "Language"
      Yast.import "Installation"

      @func = Convert.to_string(WFM.Args(0))
      @param = Convert.to_map(WFM.Args(1))
      @ret = {}

      if @func == "MakeProposal"
        @force_reset = Ops.get_boolean(@param, "force_reset", false)
        @language_changed = Ops.get_boolean(@param, "language_changed", false)

        @reinit = false
        @partition_changed = false

        if Installation.dirinstall_installing_into_dir
          # check the target directory in dirinstall mode
          if Packages.timestamp != Installation.dirinstall_target_time
            @partition_changed = true
          end
          # save information about target change time in module Packages
          Packages.timestamp = Installation.dirinstall_target_time
        else
          # check the partitioning in installation
          if Packages.timestamp != staging_revision
            # don't set flag partition_changed if it's the first "change"
            @partition_changed = true if Packages.timestamp != 0
          end
          # save information about devicegraph revision in module Packages
          Packages.timestamp = staging_revision
        end

        if Pkg.GetPackageLocale != Language.language
          @language_changed = true
          Pkg.SetPackageLocale(Language.language)
        end
        if !Builtins.contains(Pkg.GetAdditionalLocales, Language.language)
          # FIXME this is temporary fix
          #	    language_changed = true;
          Pkg.SetAdditionalLocales(
            Builtins.add(Pkg.GetAdditionalLocales, Language.language)
          )
        end

        # if only partitioning has been changed just return the current state,
        # don't reset to default (bnc#450786, bnc#371875)
        if @partition_changed && !@language_changed && !@force_reset && !Packages.PackagesProposalChanged
          return Packages.Summary([ :product, :pattern, :selection, :size, :desktop ], false);
        end

        @reinit = true if @language_changed
        Builtins.y2milestone(
          "package proposal: force reset: %1, reinit: %2, language changed: %3",
          @force_reset,
          @reinit,
          @language_changed
        )
        @ret = Packages.Proposal(
          @force_reset, # user decision: reset to default
          @reinit, # reinitialize due to language or partition change
          false
        ) # simple version

        if @language_changed && !@force_reset
          # if the  language has changed the software proposal is reset to the default settings
          if !Builtins.haskey(@ret, "warning")
            # the language_changed flag has NOT been set by the NLD frame
            @ret = Builtins.add(
              @ret,
              "warning",
              _("The software proposal is reset to the default values.")
            )
          end
        end
        if Ops.greater_than(Packages.solve_errors, 0)
          # the proposal for the packages requires manual intervention
          @ret = Builtins.union(
            @ret,
            {
              # warning text
              "warning"       => _(
                "Cannot solve dependencies automatically. Manual intervention is required."
              ),
              "warning_level" => :blocker
            }
          )
        end
      elsif @func == "AskUser"
        @has_next = Ops.get_boolean(@param, "has_next", false)

        # call some function that displays a user dialog
        # or a sequence of dialogs here:
        #
        # sequence = DummyMod::AskUser( has_next );

        @chosen_id = Ops.get(@param, "chosen_id")
        if @chosen_id == "mediacheck"
          @result = Convert.to_symbol(WFM.CallFunction("checkmedia", WFM.Args))
          @ret = { "workflow_sequence" => @result }
        else
          @result = :again
          @client_to_call = "inst_sw_select"

          while @result == :again
            @result = Convert.to_symbol(
              WFM.CallFunction(@client_to_call, [true, true])
            )
          end

          # Fill return map

          @ret = { "workflow_sequence" => @result }
        end
      elsif @func == "Description"
        # disable proposal if doing image-only installation
        return nil if Installation.image_only
        # Fill return map.
        #
        # Static values do just nicely here, no need to call a function.

        @ret = {
          # this is a heading
          "rich_text_title" => _("Software"),
          # this is a menu entry
          "menu_title"      => _("&Software"),
          "id"              => "software_stuff"
        }
      end

      deep_copy(@ret)
    end

  private

    def staging_revision
      @storage_manager ||= Y2Packager::StorageManagerProxy.new
      @storage_manager.staging_revision
    end
  end
end

Yast::SoftwareProposalClient.new.main
