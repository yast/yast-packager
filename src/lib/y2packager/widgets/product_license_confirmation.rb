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

Yast.import "Report"

module Y2Packager
  module Widgets
    # Widget for product license confirmation
    #
    # Presents a checkbox to confirm product's license. This widget will update
    # the product's license confirmation status
    class ProductLicenseConfirmation < CWM::CheckBox
      # @return [Y2Packager::Product] Product
      attr_reader :product
      # @return [Boolean] Skip value validation
      attr_reader :skip_validation

      # Constructor
      #
      # @param product [Y2Packager::Product] Product to confirm license
      def initialize(product, skip_validation: false)
        textdomain "packager"
        @product = product
        @skip_validation = skip_validation
      end

      # Widget label
      #
      # @return [String] Translated label
      # @see CWM::AbstractWidget#label
      def label
        # license agreement check box label
        _("I &Agree to the License Terms.")
      end

      # Widget options
      #
      # @see CWM::AbstractWidget#opt
      def opt
        [:notify]
      end

      # Widget value initializer
      #
      # @see CWM::AbstractWidget#init
      def init
        product.license_confirmed? ? check : uncheck
      end

      # Handle value changes
      #
      # @see CWM::AbstractWidget#handle
      # @see #store
      def handle
        store
      end

      # Update product license confirmation status
      #
      # @see CWM::AbstractWidget#store
      # @see Y2Packager::Product#license_confirmation
      def store
        return if product.license_confirmed? == value

        product.license_confirmation = value
        nil
      end

      # Validate value
      #
      # The value is not valid if license is required but not confirmed.
      # This method shows an error if validation fails.
      #
      # @return [Boolean] true if the value is valid; false otherwise
      # @see CWM::AbstractWidget#validate
      def validate
        if skip_validation || !product.license_confirmation_required? || product.license_confirmed?
          return true
        end

        Yast::Report.Message(_("You must accept the license to install this product"))
        false
      end
    end
  end
end
