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

Yast.import "UI"
Yast.import "Stage"

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
          Y2Packager::Widgets::SimpleLanguageSelection.new(selectable_locales, content_language)
      end

      # Product selection widget
      #
      # @return [Widgets::ProductLicenseContent]
      def product_license
        @product_license ||=
          Y2Packager::Widgets::ProductLicenseContent.new(product, content_language)
      end

      # Selectable license translations
      #
      # When running on textmode, the terminal is not able to display *some* languages
      # see #default_language for further details.
      #
      # @return [Array<String>] Locale codes of the available translations
      def selectable_locales
        product.license_locales.find_all { |loc| displayable_language?(loc) }
      end

      # License translation language
      #
      # If the wanted language is present among those displayable, use it,
      # otherwise use the default
      #
      # @return [String] License content language
      def content_language
        l = selectable_locales.find { |loc| language.start_with?(loc) }
        l || DEFAULT_FALLBACK_LANGUAGE
      end

      # @return [String] Fallback language
      DEFAULT_FALLBACK_LANGUAGE = "en_US".freeze

      # Whether a language is displayable
      #
      # @param lang [String] "cs" or "cs_CZ"
      # @return [Boolean]
      # @see Yast::Language.supported_language?
      def displayable_language?(lang)
        Yast::Language.supported_language?(lang)
      end
    end
  end
end
