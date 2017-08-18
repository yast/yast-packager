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

module Y2Packager
  module Dialogs
    class InstProductLicense < ::UI::InstallationDialog
      attr_reader :product

      def initialize(product)
        super()
        @product = product
      end

      def dialog_content
        VBox(
          VSpacing(0.5),
          ReplacePoint(
            Id("license_replace_point"),
            license_content
          ),
          confirmation_button
        )
      end

      def dialog_title
        format(_("%s License Agreement"), product.label)
      end

    private

      def license_content
        MinWidth(
          80,
          RichText(Id("license_content"), product.license_to_confirm)
        )
      end

      def confirmation_button
        VBox(
          VSpacing(0.5),
          Left(
            CheckBox(
              Id("license_#{product.name}"),
              Opt(:notify),
              # license agreement check box label
              _("I &Agree to the License Terms.")
            )
          )
        )
      end
    end
  end
end
