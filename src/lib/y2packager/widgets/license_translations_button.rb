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
require "y2packager/dialogs/product_license_translations"

module Y2Packager
  module Widgets
    # This button launches the licenses translations dialog when pushed
    class LicenseTranslationsButton < CWM::PushButton
      # @return [Y2Packager::Product] Product
      attr_reader :product
      attr_reader :language

      def initialize(product, language = nil)
        super()
        @product = product
        @language = language || Yast::Language.language
      end

      # Widget label
      #
      # @return [String] Translated label
      # @see CWM::AbstractWidget#label
      def label
        _("License &Translations...")
      end

      # Launch the product license translations dialog
      #
      # @see CWM::AbstractWidget#handle
      def handle
        Y2Packager::Dialogs::ProductLicenseTranslations.new(product, language).run
        nil
      end
    end
  end
end
