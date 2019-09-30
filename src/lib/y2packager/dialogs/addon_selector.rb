# ------------------------------------------------------------------------------
# Copyright (c) 2017 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require "yast"
require "erb"
require "ui/installation_dialog"

Yast.import "Report"
Yast.import "Stage"
Yast.import "UI"
Yast.import "Wizard"

module Y2Packager
  module Dialogs
    # Dialog which shows the user available products on the medium
    class AddonSelector < ::UI::InstallationDialog
      include Yast::Logger
      include ERB::Util

      # @return [Array<Y2Packager::ProductLocation>] Products on the medium
      attr_reader :products
      # @return [Array<Y2Packager::ProductLocation>] User selected products
      attr_reader :selected_products

      # TODO: handle a theoretical case when a product subdirectory contains several
      # libzypp products (only for 3rd party or manually created media, the official
      # SUSE media always contain one product per repository)

      # Constructor
      #
      # @param products [Array<Y2Packager::ProductLocation>] Products on the medium
      def initialize(products)
        super()
        textdomain "packager"

        @products = products
        # do not offer base products, they would conflict with the already selected base product,
        # allow a hidden way to force displaying them in some special cases
        @products.reject! { |p| p.details&.base } if ENV["Y2_DISPLAY_BASE_PRODUCTS"] != "1"
        @selected_products = []
      end

      # Handler for the :next action
      #
      # This action happens when the user clicks the 'Next' button
      def next_handler
        read_user_selection

        return if selected_products.empty? && !Yast::Popup.ContinueCancel(continue_msg)

        finish_dialog(:next)
      end

      # Handler for the :abort action
      # Confirm abort when running in the initial stage (inst-sys)
      def abort_handler
        return if Yast::Stage.initial && !Yast::Popup.ConfirmAbort(:painless)

        finish_dialog(:abort)
      end

      # Text to display when the help button is pressed
      #
      # @return [String]
      def help_text
        # TRANSLATORS: help text
        _("<p>The selected repository contains several products in independent " \
        "subdirectories. Select which products you want to install.</p>")
      end

      # Handle changing the current item or chaging the selection
      def addon_repos_handler
        current_item = Yast::UI.QueryWidget(Id(:addon_repos), :CurrentItem)
        current_product = products.find { |p| p.dir == current_item }

        return unless current_product

        refresh_details(current_product)

        select_dependent_products
      end

      # Display the the dialog title on the left side at installation
      # (in the first stage) to have the same layout as in the registration
      # addons dialog.
      def run
        Yast::Wizard.OpenLeftTitleNextBackDialog if Yast::Stage.initial
        super()
      ensure
        Yast::Wizard.CloseDialog if Yast::Stage.initial
      end

      # overwrite dialog creation to always enable back/next by default
      def create_dialog
        res = super
        Yast::Wizard.EnableNextButton
        Yast::Wizard.EnableBackButton

        res
      end

    private

      attr_writer :selected_products

      def selection_content
        products.map { |p| Item(Id(p.dir), p.summary || p.name) }
      end

      # Dialog content
      #
      # @see ::UI::Dialog
      def dialog_content
        VBox(
          # TRANSLATORS: Product selection label (above a multi-selection box)
          Left(Heading(_("Available Extensions and Modules"))),
          VWeight(60, MinHeight(8,
            MultiSelectionBox(
              Id(:addon_repos),
              Opt(:notify, :immediate),
              "",
              selection_content
            ))),
          VSpacing(0.4),
          details_widget
        )
      end

      # select the dependent products for the active selection
      def select_dependent_products
        # select the dependent products
        new_selection = current_selection

        # the selection has not changed, nothing to do
        return if new_selection == selected_products

        # add the dependent items to the selected list
        selected_items = Yast::UI.QueryWidget(Id(:addon_repos), :SelectedItems)
        new_items = new_selection - selected_products
        new_items.each do |p|
          # the dependencies contain also the transitive (indirect) dependencies,
          # we do not need to recursively evaluate the list
          dependencies = p&.details&.depends_on
          selected_items.concat(dependencies) if dependencies
        end

        selected_items.uniq!

        Yast::UI.ChangeWidget(:addon_repos, :SelectedItems, selected_items)
      end

      # refresh the details of the currently selected add-on
      def refresh_details(current_product)
        details = product_description(current_product)
        Yast::UI.ChangeWidget(Id(:details), :Value, details)
        Yast::UI.ChangeWidget(Id(:details), :Enabled, true)
      end

      def read_user_selection
        self.selected_products = current_selection

        log.info("Selected products: #{selected_products.inspect}")
      end

      #
      # The currently selected products
      #
      # @return [Array<Y2Packager::ProductLocation>] list of selected products
      #
      def current_selection
        selected_items = Yast::UI.QueryWidget(Id(:addon_repos), :SelectedItems)
        products.select { |p| selected_items.include?(p.dir) }
      end

      # Dialog title
      #
      # @see ::UI::Dialog
      def dialog_title
        # TODO: does it make sense also for the 3rd party addons?
        _("Extension and Module Selection")
      end

      # A message for asking the user whether to continue without adding any addon.
      #
      # @return [String] translated message
      def continue_msg
        # TRANSLATORS: Popup with [Continue] [Cancel] buttons
        _("No product has been selected.\n\n" \
          "Do you really want to continue without adding any product?")
      end

      # description widget
      # @return [Yast::Term] the addon details widget
      def details_widget
        VWeight(40, RichText(Id(:details), Opt(:disabled), "<small>" +
        description + "</small>"))
      end

      # extra help text
      # @return [String] translated text
      def description
        # TRANSLATORS: inline help text displayed below the product selection widget
        _("Select a product to see it's description here. The dependent products " \
          "are selected automatically.")
      end

      def product_description(product)
        erb_file = File.join(__dir__, "product_summary.erb")
        log.info "Loading ERB template #{erb_file}"
        erb = ERB.new(File.read(erb_file))

        # compute the dependent products
        dependencies = []
        product&.details&.depends_on&.each do |p|
          # display the human readable product name instead of the product directory
          prod = @products.find { |pr| pr.dir == p }
          dependencies << (prod.summary || prod.name) if prod
        end

        # render the ERB template in the context of this object
        erb.result(binding)
      end
    end
  end
end
