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
require "cwm"
require "cwm/dialog"
require "y2packager/widgets/product_license_translations"
require "y2packager/widgets/product_license_confirmation"

Yast.import "Language"
Yast.import "Popup"

module Y2Packager
  module Dialogs
    # Dialog which shows the user a license and ask for confirmation
    class InstProductLicense < CWM::Dialog
      # @return [Y2Packager::Product] Product
      attr_reader :product

      # @return [Array<String>] list of buttons to disable ("next_button",...)
      attr_reader :disable_buttons

      # Constructor
      #
      # @param product [Y2Packager::Product] Product to ask for the license
      # @param disable_buttons [Array<String>] list of buttons to disable
      def initialize(product, disable_buttons: [])
        super()
        textdomain "packager"

        @product = product
        @disable_buttons = disable_buttons.map { |b| "#{b}_button" }
      end

      # Returns the dialog title
      #
      # @return [String] Dialog's title
      def title
        # TRANSLATORS: %s is a product name
        format(_("%s License Agreement"), product.label)
      end

      # Dialog content
      #
      # @return [Yast::Term] Dialog's content
      def contents
        VBox(
          Widgets::ProductLicenseTranslations.new(product, Yast::Language.language),
          HBox(
            confirmation_checkbox,
            HStretch()
          )
        )
      end

      # Overwrite abort handler to ask for confirmation
      def abort_handler
        Yast::Popup.ConfirmAbort(:painless)
      end

    private

      # Return the license confirmation widget if required
      #
      # It returns Empty() if confirmation is not needed.
      #
      # @return [Yast::Term,ProductLicenseConfirmation] Product confirmation license widget
      #   or Empty() if confirmation is not needed.
      def confirmation_checkbox
        return Empty() unless product.license_confirmation_required?

        Widgets::ProductLicenseConfirmation.new(product)
      end
    end
  end
end
