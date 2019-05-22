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
          Y2Packager::Widgets::SimpleLanguageSelection.new(available_locales, content_language)
      end

      # Product selection widget
      #
      # @return [Widgets::ProductLicenseContent]
      def product_license
        @product_license ||=
          Y2Packager::Widgets::ProductLicenseContent.new(product, content_language)
      end

      # Available license translations
      #
      # When running on textmode, only the preselected/given language is considered.
      # see #default_language for further details.
      #
      # @return [Array<String>] Locale codes of the available translations
      # @see #default_language
      def available_locales
        supported_language? ? product.license_locales : [default_language]
      end

      # License translation language
      #
      # When running on textmode, it returns the preselected/default language.
      # see #default_language for further details.
      #
      # @return [String] License content language
      # @see #default_language
      def content_language
        supported_language? ? language : default_language
      end

      # @return [String] Fallback language
      DEFAULT_FALLBACK_LANGUAGE = "en_US".freeze

      # Default language
      #
      # For some languages (like Japanese, Chinese or Korean) YaST needs to use a fbiterm in order
      # to display symbols correctly when running on textmode.  However, if none of those languages
      # is selected on boot, this special terminal won't be used.
      #
      # So during 1st stage and when running in textmode, it returns the preselected language (from
      # install.inf).
      #
      # On an installed system, it prefers the given language. Finally, if the license translation
      # is not available, the fallback language is returned.
      #
      # @return [String] Language code
      def default_language
        candidate_lang = Yast::Stage.initial ? Yast::Language.preselected : language
        translated = product.license_locales.any? { |l| candidate_lang.start_with?(l) }
        return candidate_lang if translated
        DEFAULT_FALLBACK_LANGUAGE
      end

      # Whether the preselected language is supported
      #
      # It should not allow to change the language if it is a not fbiterm supported language.
      #
      # @return [Boolean]
      # @see Yast::Language.supported_language?
      def supported_language?
        Yast::Language.supported_language?(Yast::Language.preselected)
      end
    end
  end
end
