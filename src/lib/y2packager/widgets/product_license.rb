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
require "y2packager/widgets/product_license_confirmation"
require "y2packager/widgets/license_translations_button"
require "y2packager/widgets/product_license_content"

module Y2Packager
  module Widgets
    # Widget to show a product's license
    #
    # This widget relies on Y2Packager::Widgets::ProductLicenseConfirmation to
    # show the license confirmation checkbox.
    class ProductLicense < CWM::CustomWidget
      # @return [Y2Packager::Product] Product
      attr_reader :product
      # @return [Boolean] Skip value validation
      attr_reader :skip_validation

      # Constructor
      #
      # @param product [Y2Packager::Product] Product to ask for the license
      def initialize(product, language: nil, skip_validation: false)
        textdomain "packager"
        @product = product
        @language = language || Yast::Language.language
        @skip_validation = skip_validation
      end

      # Widget label
      #
      # @return [String] Translated label
      # @see CWM::AbstractWidget#label
      def label
        _("License Agreement")
      end

      # Widget content
      #
      # @see CWM::CustomWidget#contents
      def contents
        VBox(
          Left(Label(_("License Agreement"))),
          product_license_content,
          VSpacing(0.5),
          HBox(
            confirmation_checkbox,
            HStretch(),
            translations_button
          )
        )
      end

      # Translate the license content to the given language
      #
      # @param new_language [String] Language code (en_US, de_DE, etc.).
      def translate(new_language)
        self.language = new_language
        product_license_content.translate(language)
      end

    private

      # @return [String] Language code (en_US, es_ES, etc.).
      attr_accessor :language

      # Widget containing the license translated to the language determined by #language
      #
      # @return [CWM::ProductLicenseContent]
      def product_license_content
        @product_license_content ||= ProductLicenseContent.new(product, language)
      end

      # Return the license confirmation widget if required
      #
      # It returns Empty() if confirmation is not needed.
      #
      # @return [Yast::Term,ProductLicenseConfirmation] Product confirmation license widget
      #   or Empty() if confirmation is not needed.
      def confirmation_checkbox
        return Empty() unless product.license_confirmation_required?

        ProductLicenseConfirmation.new(product, skip_validation: skip_validation)
      end

      # Return the UI for the translation confirmation button
      #
      # @return [LicenseTranslationButton] License translations button
      def translations_button
        LicenseTranslationsButton.new(product)
      end
    end
  end
end
