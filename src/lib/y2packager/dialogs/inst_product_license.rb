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

module Y2Packager
  module Dialogs
    # Dialog which shows the user a license and ask for confirmation
    class InstProductLicense < CWM::Dialog
      # @return [Y2Packager::Product] Product
      attr_reader :product

      # Constructor
      #
      # @param product [Y2Packager::Product] Product to ask for the license
      def initialize(product)
        super()
        textdomain "packager"

        @product = product
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
            Left(Widgets::ProductLicenseConfirmation.new(product)),
            HStretch()
          )
        )
      end
    end
  end
end
