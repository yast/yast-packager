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

module Y2Packager
  module Widgets
    # Widget to show a product's license
    #
    # This widget relies on Y2Packager::Widgets::ProductLicenseConfirmation to
    # show the license confirmation checkbox.
    class ProductLicense < CWM::CustomWidget
      # @return [Y2Packager::Product] Product
      attr_reader :product
      # @param skip_validation [Boolean] Skip value validation
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
          license_content,
          confirmation_checkbox
        )
      end

    private

      # @return [String] Language code (en_US, es_ES, etc.).
      attr_accessor :language

      # Return the UI for the license content
      #
      # @return [Yast::Term] UI for the license content
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
      #
      # It returns Empty() if confirmation is not needed.
      #
      # @return [Yast::Term] Product confirmation license widget or Empty() if
      #   confirmation is not needed.
      def confirmation_checkbox
        return Empty() unless product.license_confirmation_required?

        VBox(
          VSpacing(0.5),
          Left(
            ProductLicenseConfirmation.new(product, skip_validation: skip_validation)
          )
        )
      end
    end
  end
end
