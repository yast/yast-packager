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

      # @return [Array<Y2Packager::ProductLocation>] Products on the medium
      attr_reader :products
      # @return [Array<Y2Packager::ProductLocation>] User selected products
      attr_reader :selected_products

      # Constructor
      #
      # @param products [Array<Y2Packager::ProductLocation>] Products on the medium
      def initialize(products)
        super()
        textdomain "packager"

        @products = products
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
        # TRANSLATORS: help text (1/2)
        _("<p>The selected repository contains several products in independent " \
        "subdirectories. Select which products you want to install.</p>") +
          # TRANSLATORS: help text (2/2)
          _("<p>Note: If there are dependencies between the products you have " \
          "to manually select the dependent products. The product dependencies "\
          "cannot be automatically detected and checked.</p>")
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
        products.map(&:name)
      end

      # Dialog content
      #
      # @see ::UI::Dialog
      def dialog_content
        VBox(
          # TRANSLATORS: Product selection label (above a multi-selection box)
          Left(Heading(_("Available Extensions and Modules"))),
          VWeight(75, MinHeight(12,
            MultiSelectionBox(
              Id("addon_repos"),
              "",
              selection_content
            ))),
          VSpacing(0.4),
          details_widget
        )
      end

      def read_user_selection
        selected_items = Yast::UI.QueryWidget(Id("addon_repos"), :SelectedItems)

        self.selected_products = products.select { |p| selected_items.include?(p.name) }

        log.info("Selected products: #{selected_products.inspect}")
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
        MinHeight(3,
          VWeight(25, RichText(Id(:details), Opt(:disabled), "<small>" +
          description + "</small>")))
      end

      # extra help text
      # @return [String] translated text
      def description
        # TRANSLATORS: inline help text displayed below the product selection widget
        _("The dependencies between products are not handled automatically. " \
          "The dependent modules or extensions must be selected manually.")
      end
    end
  end
end
