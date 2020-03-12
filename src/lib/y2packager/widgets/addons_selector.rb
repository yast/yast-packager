# Copyright (c) [2020] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "forwardable"
require "cwm/multi_status_selector"

module Y2Packager
  module Widgets
    # A custom widget to display a multi status selector list
    class AddonsSelector < CWM::MultiStatusSelector
      include Yast::Logger
      include Yast::UIShortcuts

      attr_reader :items

      # Constructor
      #
      # @param products [Array<ProductLocation>] available product locations
      # @param preselected_products [Array<ProductLocation>] product locations to be selected
      def initialize(products, preselected_products)
        @products = products
        @items = products.map do |product|
          dependencies = product&.details&.depends_on || []
          selected = preselected_products.include?(product)

          Item.new(product, dependencies, selected)
        end
      end

      # (see CWM::AbstractWidget#contents)
      def contents
        VBox(
          VWeight(60, super),
          VWeight(40, details_widget)
        )
      end

      # Toggles the item
      #
      # Also recalculates the dependencies to perform necessary auto selections
      #
      # @param item [Item] the item to toggle
      def toggle(item)
        item.toggle
        refresh_details(item)
        select_dependencies
      end

      # Returns selected and auto-selected items
      #
      # @return [Array<Item>] a collection of selected and auto-selected items
      def selected_items
        items.select { |i| i.selected? || i.auto_selected? }
      end

      # (see CWM::AbstractWidget#contents)
      def help
        Item.help
      end

    private

      # (see CWM::MultiStatusSelector#label_event_handler)
      def label_event_handler(item)
        refresh_details(item)
      end

      # Updates the details area with the given item description
      #
      # @param item [Item] selected item
      def refresh_details(item)
        details_widget.value = item.description
      end

      # Auto-selects needed dependencies
      #
      # Based in the current selection, auto selects dependencies not manually
      # selected yet.
      def select_dependencies
        # Resets previous auto selection
        @items.select(&:auto_selected?).each(&:unselect!)

        # Recalculates missed dependencies
        selected_items = @items.select(&:selected?)
        dependencies = selected_items.flat_map(&:dependencies).uniq
        missed_dependencies = dependencies - selected_items.map(&:id)

        # Auto-selects them
        @items.select { |i| missed_dependencies.include?(i.id) }.each(&:auto_select!)
      end

      # Returns the widget to display the details
      #
      # @return [CWM::RichText] the widget to display the details
      def details_widget
        @details_widget ||=
          begin
            w = CWM::RichText.new
            w.widget_id = "details_area"
            w
          end
      end

      # Internal class to represent a {Y2Packager::ProductLocation} as selectable item
      class Item < Item
        include Yast::Logger
        include ERB::Util
        include Yast::I18n

        # Constructor
        #
        # @param product [Y2Packager::ProductLocation] the product to be represented
        # @param dependencies [Array<String>] a collection with the dependencies ids
        # @param selected [Boolean] a flag indicating the initial status for the item
        def initialize(product, dependencies, selected)
          @product = product
          @dependencies = dependencies
          @status = selected ? :selected : :unselected
        end

        attr_reader :dependencies, :status

        # Returns the item id
        #
        # @return [String] the item id
        def id
          product.dir
        end

        # Returns the item label
        #
        # @return [String] the item label
        def label
          product.summary || product.name
        end

        # Builds the item description
        def description
          @description ||=
            begin
              erb_file = File.join(__dir__, "product_summary.erb")
              log.info "Loading ERB template #{erb_file}"
              erb = ERB.new(File.read(erb_file))

              erb.result(binding)
            end
        end

      private

        attr_reader :product
      end
    end
  end
end
