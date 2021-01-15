# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE LLC
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact SUSE.
#
# To contact SUSE about this file by physical or electronic mail, you may find
# current contact information at www.suse.com.
# ------------------------------------------------------------------------------

require "installation/proposal_client"
require "y2packager/storage_manager_proxy"

module Yast
  # Software installation proposal
  class SoftwareProposalClient < ::Installation::ProposalClient
    def initialize
      Yast.import "Pkg"
      textdomain "packager"

      Yast.import "Packages"
      Yast.import "Language"
      Yast.import "Mode"
      Yast.import "Installation"
      Yast.import "AutoinstData"
    end

    def make_proposal(flags)
      @force_reset = flags.fetch("force_reset", false)

      @language_changed = adjust_locales
      @language_changed ||= flags.fetch("language_changed", false)

      # if only partitioning has been changed just return the current state,
      # don't reset to default (bnc#450786, bnc#371875)
      if partitioning_changed? && !@language_changed && !@force_reset &&
          !Packages.PackagesProposalChanged
        @ret = Packages.Summary([:product, :pattern, :selection, :size, :desktop], false)
      else
        @reinit = @language_changed
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
      end

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

      # The Default warning_level is "error". So the user can continue
      # installation.
      add_warning_if_needed(Packages.check_ntp_installation_packages)
      add_warning_if_needed(Packages.check_remote_installation_packages)
      # AY: Checking if second stage is needed and the environment has been setup.
      add_warning_if_needed(Yast::AutoinstData.autoyast_second_stage_error) if Yast::Mode.auto

      @ret
    end

    def ask_user(params)
      chosen_id = params["chosen_id"]
      if chosen_id == "mediacheck"
        @result = Convert.to_symbol(WFM.CallFunction("checkmedia", WFM.Args))
      else
        @result = :again
        @client_to_call = "inst_sw_select"

        while @result == :again
          @result = Convert.to_symbol(
            WFM.CallFunction(@client_to_call, [true, true])
          )
        end
      end
      @ret = { "workflow_sequence" => @result }
    end

    def description
      # disable proposal if doing image-only installation
      return nil if Installation.image_only

      {
        # this is a heading
        "rich_text_title" => _("Software"),
        # this is a menu entry
        "menu_title"      => _("&Software"),
        "id"              => "software_stuff"
      }
    end

  private

    # @param msg [String] warning message to be added
    #
    # @note The message could be a frozen string (e.g., translated messages).
    def add_warning_if_needed(msg)
      return if msg.empty?

      if @ret.key?("warning")
        @ret["warning"] += "\n#{msg}"
      else
        @ret["warning"] = msg
      end
    end

    def partitioning_changed?
      changed = false

      if Installation.dirinstall_installing_into_dir
        # check the target directory in dirinstall mode
        changed = true if Packages.timestamp != Installation.dirinstall_target_time
        # save information about target change time in module Packages
        Packages.timestamp = Installation.dirinstall_target_time
      else
        # check the partitioning in installation
        if Packages.timestamp != staging_revision
          # don't set changed if it's the first "change"
          changed = true if Packages.timestamp.nonzero?
        end
        # save information about devicegraph revision in module Packages
        Packages.timestamp = staging_revision
      end

      log.info "partitioning_changed? - #{changed}"
      changed
    end

    # Current revision of the staging storage devicegraph
    #
    # @return [Integer]
    def staging_revision
      @storage_manager ||= Y2Packager::StorageManagerProxy.new
      @storage_manager.staging_revision
    end

    # Adjust package locales
    # @return [Boolean] has the language changed
    def adjust_locales
      language_changed = false
      if Pkg.GetPackageLocale != Language.language
        language_changed = true
        Pkg.SetPackageLocale(Language.language)
      end
      if !Builtins.contains(Pkg.GetAdditionalLocales, Language.language)
        # FIXME: this is temporary fix
        #      language_changed = true;
        Pkg.SetAdditionalLocales(
          Builtins.add(Pkg.GetAdditionalLocales, Language.language)
        )
      end
      language_changed
    end
  end
end
