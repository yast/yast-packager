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
require "cwm/dialog"
require "y2packager/widgets/product_license_translations"

Yast.import "Label"

module Y2Packager
  module Dialogs
    # This dialog displays available translation for a given product.
    #
    # The dialog is open as a pop-up (check #should_open_dialog,
    # #wizard_create_dialog and #layout for technical details) and it relies
    # heavily on the {Y2Packager::Widgets::ProductLicenseTranslations} widget.
    class ProductLicenseTranslations < CWM::Dialog
      # @return [Y2Packager::Product] Product
      attr_reader :product
      # @return [String] Default language code (eg. "en_US")
      attr_reader :language

      # @param product  [Y2Packager::Product] Product
      # @param language [String] Default language code (eg. "en_US")
      def initialize(product, language = nil)
        super()
        @product = product
        @language = language || Yast::Language.language
      end

      # Returns the dialog title
      #
      # @return [String] Dialog's title
      def title
        _("License Agreement")
      end

      # Dialog content
      #
      # @return [Yast::Term] Dialog's content
      def contents
        VBox(
          Y2Packager::Widgets::ProductLicenseTranslations.new(product, language)
        )
      end

    private

      # Force the dialog to be shown as a pop-up
      #
      # @return [True]
      def should_open_dialog?
        true
      end

      # Redefine how the dialog should be created
      #
      # @see #layout
      def wizard_create_dialog(&block)
        Yast::UI.OpenDialog(layout)
        block.call
      ensure
        Yast::UI.CloseDialog()
      end

      # Define widget's layout
      #
      # @return [Yast::Term]
      def layout
        HBox(
          VSpacing(Yast::UI.TextMode ? 21 : 25),
          VBox(
            Left(
              # TRANSLATORS: dialog caption
              Heading(Id(:title), _("License Agreement"))
            ),
            VSpacing(Yast::UI.TextMode ? 0.1 : 0.5),
            HSpacing(82),
            HBox(
              VStretch(),
              ReplacePoint(Id(:contents), Empty())
            ),
            ButtonBox(
              PushButton(Id(:next), Opt(:okButton, :default, :key_F10), next_button)
            )
          )
        )
      end

      # Define next button (ok) label
      #
      # @return [String]
      def next_button
        Yast::Label.OKButton
      end
    end
  end
end
