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
require "y2packager/widgets/simple_language_selection"
require "y2packager/widgets/product_license"

module Y2Packager
  module Widgets
    # This widget display license translations for a given product
    #
    # The widget serves a glue between a pair of widgets:
    #
    # * {Y2Packager::Widgets::SimpleLanguageSelector} to select the language,
    # * {Y2Packager::Widgets::ProductLicenseContent} to display the license.
    class ProductLicenseTranslations < CWM::CustomWidget
      # @return [Y2Packager::Product] Product
      attr_reader :product
      # @return [String] Language code (en_US, es_ES, etc.).
      attr_reader :language

      # @param product  [Y2Packager::Product] Product
      # @param language [String]              Default language (en_US, es_ES, etc.).
      def initialize(product, language)
        super()
        @product = product
        @language = language
        self.handle_all_events = true
      end

      # Widget content
      #
      # @see CWM::CustomWidget#contents
      def contents
        VBox(
          Left(language_selection),
          VSpacing(0.5),
          product_license
        )
      end

      # Event handler
      #
      # Translate the license content if language has changed.
      #
      # @param event [Hash] Event data
      def handle(event)
        if event["ID"] == language_selection.widget_id
          product_license.translate(language_selection.value)
        end
        nil
      end

    private

      # Language selection widget
      #
      # @return [Y2Packager::Widgets::SimpleLanguageSelection]
      def language_selection
        @language_selection ||=
          Y2Packager::Widgets::SimpleLanguageSelection.new(product.license_locales, language)
      end

      # Product  selection widget
      #
      # @return [Widgets::ProductLicenseContent]
      def product_license
        @product_license ||=
          Y2Packager::Widgets::ProductLicenseContent.new(product, language)
      end
    end
  end
end
