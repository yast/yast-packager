# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE LLC
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
require "y2packager/medium_type"

Yast.import "GetInstArgs"
Yast.import "Packages"
Yast.import "PackageCallbacks"
Yast.import "Popup"

module Y2Packager
  module Clients
    # Client to initialize software repositories
    #
    # It is intended to be used before the inst_complex_welcome client.
    # If more than one product is available in the installation media, unselects
    # all of them (the user should set a product later).
    #
    # @see adjust_base_product_selection
    class InstRepositoriesInitialization
      include Yast::Logger
      include Yast::I18n

      # Client main method
      def main
        textdomain "packager"

        # no changes if going back
        return :back if Yast::GetInstArgs.going_back

        if Y2Packager::MediumType.skip_step?
          log.info "Skipping the client on the #{Y2Packager::MediumType.type} medium"
          return :auto
        end

        # for the Full medium we need to just add the self-update add-on
        # repo to make the new roles work
        if Y2Packager::MediumType.offline?
          if Y2Packager::SelfUpdateAddonRepo.present?
            log.info "Adding the self-update add-on repository..."
            Y2Packager::SelfUpdateAddonRepo.create_repo
          else
            log.info "Self-update repository not found - finishing..."
          end

          return :auto
        end

        if !init_installation_repositories
          Yast::Popup.Error(
            _("Failed to initialize the software repositories.\nAborting the installation.")
          )
          return :abort
        end

        if products.empty?
          Yast::Popup.Error(
            _("Unable to find base products to install.\nAborting the installation.")
          )
          return :abort
        end

        adjust_base_product_selection

        # in an online installation and we need to additionally load and initialize
        # the workflow for the registered base product
        merge_and_run_workflow if Y2Packager::MediumType.online?

        :next
      end

    private

      # Initialize installation repositories
      def init_installation_repositories
        Yast::PackageCallbacks.RegisterEmptyProgressCallbacks
        # the online installation uses the repositories from the registration server,
        # skip initializing the repository from the medium, it is missing there
        Yast::Packages.InitializeCatalogs unless Y2Packager::MediumType.online?
        return false if Yast::Packages.InitFailed

        Yast::Packages.InitializeAddOnProducts

        # bnc#886608: Adjusting product name (for &product; macro) right after we
        # initialize libzypp and get the base product name (intentionally not translated)
        # FIXME: UI.SetProductName(Product.name || "SUSE Linux")
        Yast::PackageCallbacks.RestorePreviousProgressCallbacks

        # add extra addon repo built from the initial self update repository (bsc#1101016)
        Y2Packager::SelfUpdateAddonRepo.create_repo if Y2Packager::SelfUpdateAddonRepo.present?

        true
      end

      # Merge selected product's workflow and go to the next step
      #
      # @see Yast::WorkflowManager.merge_product_workflow
      def merge_and_run_workflow
        Yast::WorkflowManager.SetBaseWorkflow(false)
        Yast::WorkflowManager.merge_product_workflow(Y2Packager::ProductSpec.selected_base.to_product)
        Yast::ProductControl.RunFrom(Yast::ProductControl.CurrentStep + 1, true)
      end

      # Adjust product selection
      #
      # During installation, all products are selected by default. So if there
      # is more than 1, we should unselect them all. The user will select one
      # later.
      #
      # On the other hand, if only one product is available, we should make
      # sure that it is selected for installation because, during upgrade, it
      # is not automatically selected.
      #
      # @see https://github.com/yast/yast-packager/blob/7e1a0bbb90823b03c15d92f408036a560dca8aa3/src/modules/Packages.rb#L1876
      # @see https://github.com/yast/yast-packager/blob/fbc396df910e297915f9f785fc460e72e30d1948/src/modules/Packages.rb#L1905
      def adjust_base_product_selection
        forced_base_product = Y2Packager::ProductSpec.forced_base_product&.to_product

        if forced_base_product
          log.info("control.xml wants to force the #{forced_base_product.name} product")

          forced_base_product.select
          discarded_products = products.reject { |p| p == forced_base_product }

          log.info("Ignoring the other products: #{discarded_products.inspect}")
        elsif products.size == 1
          products.first.select
        else
          products.each(&:restore) unless Y2Packager::MediumType.online?
        end
      end

      # Return base available products
      #
      # @return [Array<Y2Packager::ProductSpec>] Available base products
      def products
        @products ||= Y2Packager::ProductSpec.base_products.map(&:to_product)
      end
    end
  end
end
