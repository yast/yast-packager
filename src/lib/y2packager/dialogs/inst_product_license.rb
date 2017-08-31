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
require "cgi/util"
Yast.import "Language"
Yast.import "UI"
Yast.import "Report"

module Y2Packager
  module Dialogs
    # Dialog which shows the user a license and ask for confirmation
    class InstProductLicense < ::UI::InstallationDialog
      # @return [Y2Packager::Product] Product
      attr_reader :product

      # Constructor
      #
      # @param product [Y2Packager::Product] Product to ask for the license
      def initialize(product)
        super()
        @product = product
        self.language = Yast::Language.language
        self.confirmed = product.license_confirmed?
      end

      # Handler for the :language action
      #
      # This happens when the user changes the license language
      def language_handler
        self.language = Yast::UI.QueryWidget(Id(:language), :Value)
        Yast::UI.ReplaceWidget(Id(:license_replace_point), license_content)
      end

      # Handler for the :license_confirmation action
      #
      # This action happens when the user clicks the confirmation checkbox.
      def license_confirmation_handler
        @confirmed = Yast::UI.QueryWidget(Id(:license_confirmation), :Value)
      end

      # Handler for the :next action
      #
      # This action happens when the user clicks the 'Next' button
      def next_handler
        if confirmed
          update_product_confirmation
          finish_dialog(:next)
        else
          Yast::Report.Message(_("You must accept the license to install this product"))
        end
      end

      # Handler for the :next action
      #
      # This action happens when the user clicks the 'Back' button
      def back_handler
        update_product_confirmation
        finish_dialog(:back)
      end

    private

      # @return [String] Language code (en_US, es_ES, etc.).
      attr_accessor :language
      # @return [Boolean] Determines whether the user confirmed the license
      attr_accessor :confirmed

      # Dialog content
      #
      # @see ::UI::Dialog
      def dialog_content
        VBox(
          Left(language_selection),
          VSpacing(0.5),
          ReplacePoint(
            Id(:license_replace_point),
            license_content
          ),
          confirmation_checkbox
        )
      end

      # Dialog title
      #
      # @see ::UI::Dialog
      def dialog_title
        format(_("%s License Agreement"), product.label)
      end

      # Return the UI for the language selector
      def language_selection
        ComboBox(
          Id(:language),
          Opt(:notify, :hstretch),
          _("&License Language"),
          Yast::Language.GetLanguageItems(:primary)
        )
      end

      # Return the UI for the license content
      def license_content
        MinWidth(
          80,
          RichText(Id(:license_content), formatted_license_text)
        )
      end

      # Regexp to determine whether the text is formatted as richtext
      RICHTEXT_REGEXP = /<\/.*>/

      # Return the license text
      #
      # It detects whether license text is richtext or not and format it
      # accordingly.
      #
      # @return [String] Formatted license text
      def formatted_license_text
        text = product.license(language)
        if RICHTEXT_REGEXP =~ text
          text
        else
          "<pre>#{CGI.escapeHTML(text)}</pre>"
        end
      end

      # Return the UI for the confirmation checkbox
      def confirmation_checkbox
        VBox(
          VSpacing(0.5),
          Left(
            CheckBox(
              Id(:license_confirmation),
              Opt(:notify),
              # license agreement check box label
              _("I &Agree to the License Terms."),
              confirmed
            )
          )
        )
      end

      # Update the product's license confirmation status
      #
      # It will not update the status if it has not changed.
      def update_product_confirmation
        return if product.license_confirmed? == confirmed
        product.license_confirmation = confirmed
      end
    end
  end
end
