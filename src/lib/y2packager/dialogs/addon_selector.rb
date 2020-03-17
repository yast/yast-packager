# Copyright (c) [2017-2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "cwm/dialog"
require "y2packager/resolvable"
require "y2packager/widgets/addons_selector"

Yast.import "AddOnProduct"
Yast.import "Mode"
Yast.import "ProductFeatures"
Yast.import "Stage"
Yast.import "Wizard"

module Y2Packager
  module Dialogs
    # Dialog which shows the user available products on the medium
    class AddonSelector < ::CWM::Dialog
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
        textdomain "packager"

        @products = products
        # do not offer base products, they would conflict with the already
        # selected base product, allow a hidden way to force displaying them in
        # some special cases
        @products.reject! { |p| p.details&.base } if ENV["Y2_DISPLAY_BASE_PRODUCTS"] != "1"
        @selected_products = []
      end

      # The dialog entry point
      #
      # Display the dialog title on the left side at installation (in the first
      # stage) to have the same layout as in the registration addons dialog.
      #
      # @see CWM::Dialog#run
      def run
        Yast::Wizard.OpenLeftTitleNextBackDialog if Yast::Stage.initial
        super
      ensure
        Yast::Wizard.CloseDialog if Yast::Stage.initial
      end

      # @see CWM::Dialog#title
      def title
        # TODO: does it make sense also for the 3rd party addons?
        _("Extension and Module Selection")
      end

      # @see CWM::Dialog#contents
      def contents
        VBox(
          # TRANSLATORS: Product selection label (above a multi-selection box)
          Left(Heading(_("Available Extensions and Modules"))),
          addons_selector_widget
        )
      end

      # Handler for the :next action
      #
      # Displays a confirmation popup if none product has been selected
      #
      # @return [Boolean] true when continuing; false if the action is canceled
      def next_handler
        read_user_selection

        return true unless selected_products.empty?

        Yast::Popup.ContinueCancel(continue_msg)
      end

      # Handler for the :abort action
      #
      # Displays a confirmation popup when running in the initial stage (inst-sys)
      #
      # @return [Boolean] true when aborting is confirmed; false otherwise
      def abort_handler
        return true unless Yast::Stage.initial

        Yast::Popup.ConfirmAbort(:painless)
      end

      # Text to display when the help button is pressed
      #
      # @return [String] help
      def help
        [
          # TRANSLATORS: Help text for the product selector dialog
          _("<p>The selected repository contains several products in independent " \
          "subdirectories. Select which products you want to install.</p>"),
          # TRANSLATORS: Help text explaining different product selection statuses
          _("<p>Bear in mind that products can have several states depending on " \
            "how they were selected to be installed or not. Basically, it can be "\
            "auto-selected by a pre-selection of recommended products or as a dependency "\
            "of another product, manually selected by the user, or not selected "\
            "(see the legend below).</p>")
        ].join
      end

    private

      # @return [Array<Y2Packager::ProductLocation>] collection of selected products
      attr_writer :selected_products

      # Addons selector widget
      #
      # @return [Y2Packager::Widgets::AddonsSelector]
      def addons_selector_widget
        @addons_selector_widget ||= Widgets::AddonsSelector.new(products, preselected_products)
      end

      # Reads the currently selected products
      def read_user_selection
        selected_items = addons_selector_widget.selected_items.map(&:id)

        self.selected_products = products.select { |p| selected_items.include?(p.dir) }

        log.info("Selected products: #{selected_products.inspect}")
      end

      # A message for asking the user whether to continue without adding any addon
      #
      # @return [String] translated message
      def continue_msg
        # TRANSLATORS: Popup with [Continue] [Cancel] buttons
        _("No product has been selected.\n\n" \
          "Do you really want to continue without adding any product?")
      end

      # Returns a list of the preselected products depending on the installation mode
      #
      # @see #preselected_installation_products
      # @see #preselected_upgrade_products
      #
      # @return [Array<Y2Packager::ProductLocation>] preselected products
      def preselected_products
        if Yast::Mode.installation
          # in installation preselect the defaults defined in the control.xml/installation.xml
          preselected_installation_products
        elsif Yast::Mode.update
          # at upgrade preselect the installed addons
          preselected_upgrade_products
        else
          # in other modes (e.g. installed system) do not preselect anything
          []
        end
      end

      # Returns a list of the preselected products at upgrade
      #
      # Preselect the installed products
      #
      # @return [Array<Y2Packager::ProductLocation>] preselected products
      def preselected_upgrade_products
        missing_products = Yast::AddOnProduct.missing_upgrades
        # installed but not selected yet products (to avoid duplicates)
        products.select do |p|
          missing_products.include?(p.details&.product)
        end
      end

      # Return a list of the preselected products at installation,
      #
      # Preselect the default products specified in the control.xml/installation.xml,
      # the already selected products are ignored.
      #
      # @return [Array<Y2Packager::ProductLocation>] preselected products
      def preselected_installation_products
        default_modules = Yast::ProductFeatures.GetFeature("software", "default_modules")
        return [] unless default_modules.is_a?(Array)

        log.info("Defined default modules: #{default_modules.inspect}")
        # skip the already selected products (to avoid duplicates)
        selected_products = Y2Packager::Resolvable.find(kind: :product, status: :selected)
          .map(&:name)
        default_modules -= selected_products
        log.info("Using default modules: #{default_modules.inspect}")

        # select the default products
        products.select do |p|
          default_modules.include?(p.details&.product)
        end
      end
    end
  end
end
