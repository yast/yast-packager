# encoding: utf-8

# Module:		inst_sw_select.ycp
#
# Authors:		Gabriele Strattner <gs@suse.de>
#			Klaus Kaempf <kkaempf@suse.de>
#
# Purpose:
# Displays software selection screen. Show radioboxes for software
# main categories. Let the user select the software.
#
# Packages module read:
#
# Packages module write:
#
# $Id$
#
module Yast
  class InstSwSelectClient < Client
    def main
      Yast.import "Pkg"
      textdomain "packager"

      Yast.import "Packages"
      Yast.import "PackagesUI"

      @ret = :again

      while @ret == :again
        # add additional (internal) packages, like kernel etc.
        # they are added by proposal!!!! (#155819)
        #	Pkg::DoProvide (Packages::ComputeSystemPackageList());
        Pkg.PkgSolve(false)

        while @ret == :again
          # display the installation summary in case there is a solver problem (bnc#436721)
          if Ops.greater_than(Packages.solve_errors, 0)
            Builtins.y2milestone("Unresolved conflicts, using summary mode")
            @ret = PackagesUI.RunPackageSelector({ "mode" => :summaryMode })
          else
            @ret = PackagesUI.RunPatternSelector
          end

          Builtins.y2milestone("Package selector result: %1", @ret)

          if @ret == :accept
            # Package proposal cache has to be reset and recreated
            # from scratch. See BNC #436925.
            Packages.ResetProposalCache

            Packages.base_selection_modified = true
            @ret = :next
            Packages.solve_errors = 0 # all have been either solved
            # or marked to ignore
          end
        end
      end

      @ret
    end
  end
end

Yast::InstSwSelectClient.new.main
