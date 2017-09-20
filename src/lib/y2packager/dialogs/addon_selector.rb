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

Yast.import "UI"
Yast.import "Report"

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
      # @param product [Array<Y2Packager::ProductLocation>] Products on the medium
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
        finish_dialog(:next)
      end

      # Handler for the :next action
      # The default implementation asks for confirmation, here we abort only
      # adding an addon-on, not the whole installation.
      def abort_handler
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

    private

      attr_writer :selected_products

      def selection_content
        products.map(&:name)
      end

      # Dialog content
      #
      # @see ::UI::Dialog
      def dialog_content
        # do not stretch the MultiSelectionBox widget over the entire screen,
        # squash it to as small as possible size...
        HVSquash(
          # ...and then set a resonable minimum size
          MinSize(60, 16,
            MultiSelectionBox(
              Id("addon_repos"),

              # TRANSLATORS: Product selection label (multi-selection box)
              _("&Select Products to Install"),
              selection_content
            ))
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
    end
  end
end
