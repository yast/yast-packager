# ------------------------------------------------------------------------------
# Copyright (c) 2021 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# ------------------------------------------------------------------------------

require "yast"
require "y2packager/product"
require "y2packager/self_update_addon_repo"

Yast.import "GetInstArgs"
Yast.import "WorkflowManager"

module Y2Packager
  module Clients
    # Client to initialize product specific workflow
    class InstProductWorkflow
      include Yast::Logger
      include Yast::I18n

      # Client main method
      def main
        textdomain "packager"

        # no changes if going back
        return :back if Yast::GetInstArgs.going_back

        # Add self update repo as it can contain updated rpms for product
        if Y2Packager::SelfUpdateAddonRepo.present?
          log.info "Adding the self-update add-on repository..."
          Y2Packager::SelfUpdateAddonRepo.create_repo
        else
          log.info "Self-update repository not found - finishing..."
        end

        # initialize the workflow for the selected base product
        merge_and_run_workflow

        :next
      end

    private

      # Merge selected product's workflow and go to the next step
      #
      # @see Yast::WorkflowManager.merge_product_workflow
      def merge_and_run_workflow
        Yast::WorkflowManager.SetBaseWorkflow(false)
        Yast::WorkflowManager.merge_product_workflow(Y2Packager::Product.selected_base)
        Yast::ProductControl.RunFrom(Yast::ProductControl.CurrentStep + 1, true)
      end
    end
  end
end
