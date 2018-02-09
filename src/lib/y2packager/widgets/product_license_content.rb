# ------------------------------------------------------------------------------
# Copyright (c) 2018 SUSE LLC, All Rights Reserved.
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

module Y2Packager
  module Widgets
    # Widget to show a product's license content
    class ProductLicenseContent < CWM::CustomWidget
      # @return [Y2Packager::Product] Product
      attr_reader :product
      # @return [String] Language code (en_US, es_ES, etc.).
      attr_reader :language

      # @param product  [Y2Packager::Product] Product
      # @param language [String]              Default language (en_US, es_ES, etc.).
      def initialize(product, language)
        textdomain "packager"
        @product = product
        @language = language
      end

      # Implement #init content
      #
      # @see CWM::AbstractWidget#init
      def init
        update_license_text
      end

      # Return the UI for the widget
      #
      # @return [Yast::Term] widget's UI
      def contents
        @contents ||= MinWidth(80, license_content)
      end

      # Translate license content
      #
      # @param new_language [String] New language code
      def translate(new_language)
        return if language == new_language
        self.language = new_language
        update_license_text
      end

    private

      # @!method language=
      #   @param new_language [String] Language code
      attr_writer :language

      # License content UI
      #
      # @return [Yast::Term] UI for the license content
      def license_content
        @license_content ||= CWM::RichText.new.tap { |r| r.value = formatted_license_text }
      end

      # Update license text
      #
      # @see #license_content
      def update_license_text
        license_content.value = formatted_license_text
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
    end
  end
end
