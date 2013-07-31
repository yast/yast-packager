# encoding: utf-8

# Module: 		inst_packages.ycp
# Authors:		Stefan Hundhammer <sh@suse.de>
# Purpose:             Show the package installation dialog
#
# $Id$
#
module Yast
  class InstPackagesClient < Client
    def main
      textdomain "packager"

      Yast.import "PackagesUI"
      Yast.import "Stage"
      Yast.import "Mode"

      #/////////////////////////////////////////////////////////////////////////
      # MAIN
      #/////////////////////////////////////////////////////////////////////////

      @result = :cancel

      Builtins.y2warning(
        "Warning: inst_packages.ycp client is obsoleted, use module PackagesUI.ycp instead"
      )
      Builtins.y2milestone(
        "Stage: %1, Mode: %2, Args: %3",
        Stage.stage,
        Mode.mode,
        WFM.Args
      )

      # installation or update from a running system (there is a "Pattern Selection" button) (#229951)
      if Builtins.size(WFM.Args) == 0 &&
          (Stage.initial || Stage.normal && Mode.update)
        @result = patternSelection
      else
        if Ops.greater_than(Builtins.size(WFM.Args), 0) &&
            Ops.is_map?(WFM.Args(0))
          Builtins.y2milestone(
            "inst_packages called with options: %1",
            WFM.Args
          )

          @mode = nil
          @repo_mgr = nil

          # the options may be passed in a map or in a list
          if Ops.is_map?(WFM.Args(0))
            @opts = Convert.to_map(WFM.Args(0))
            @mode = Ops.get_symbol(@opts, "dialog_type", :searchMode)
            @repo_mgr = Ops.get_boolean(@opts, "repo_mgmt", false)
          elsif Ops.is_symbol?(WFM.Args(0))
            @mode = Convert.to_symbol(WFM.Args(0))

            @repo_mgr = WFM.Args(1) == :repoMgr if Ops.is_symbol?(WFM.Args(1))
          end

          @mode = :searchMode if @mode == nil

          @repo_mgr = Mode.normal if @repo_mgr == nil

          if @mode == :patternSelector || @mode == :pattern
            @result = patternSelection
          else
            @result = detailedSelection(@mode, @repo_mgr, nil)
          end
        else
          @result = detailedSelection(:searchMode, false, nil)
        end
      end

      @result
    end

    # Start the detailed package selection. If 'mode' is non-nil, it will be
    # passed as an option to the PackageSelector widget.
    #
    # Returns `accept or `cancel .
    #
    def detailedSelection(mode, enable_repo_mgr, display_support_status)
      options = {
        "mode"                   => mode,
        "enable_repo_mgr"        => enable_repo_mgr,
        "display_support_status" => display_support_status
      }

      PackagesUI.RunPackageSelector(options)
    end

    # Start the pattern selection dialog. If the UI does not support the
    # PatternSelector, start the detailed selection with "selections" as the
    # initial view.
    #
    def patternSelection
      PackagesUI.RunPatternSelector
    end
  end
end

Yast::InstPackagesClient.new.main
