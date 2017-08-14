# encoding: utf-8

# Module:		software_simple_proposal.ycp
#
# Author:		Klaus Kaempf <kkaempf@suse.de>
#
# Purpose:		Proposal function dispatcher - software.
#
#			See also file proposal-API.txt for details.
#
# $Id$
#
module Yast
  class SoftwareSimpleProposalClient < Client
    def main
      textdomain "packager"

      Yast.import "Packages"

      @func = Convert.to_string(WFM.Args(0))
      @param = Convert.to_map(WFM.Args(1))
      @ret = {}

      if @func == "MakeProposal"
        @force_reset = Ops.get_boolean(@param, "force_reset", false)
        @language_changed = Ops.get_boolean(@param, "language_changed", false)

        Builtins.y2milestone(
          "package proposal: force reset: %1, reinit: %2, language changed: %3",
          @force_reset,
          false,
          @language_changed
        )

        @ret = Packages.Proposal(
          false, # user decision: reset to default
          false, # reinitialize due to language or partition change
          true
        )

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
            # warning text
            "warning"       => _(
              "Cannot solve dependencies automatically. Manual intervention is required."
            ),
            "warning_level" => :blocker
          )
        end
        return deep_copy(@ret)
      else
        return WFM.CallFunction("software_proposal", [@func, @param])
      end

      deep_copy(@ret)
    end
  end
end

Yast::SoftwareSimpleProposalClient.new.main
