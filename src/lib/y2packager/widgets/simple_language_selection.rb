# ------------------------------------------------------------------------------
# Copyright (c) 2018 SUSE LINUX GmbH, Nuernberg, Germany.
#
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, contact Novell, Inc.
#
# To contact Novell about this file by physical or electronic mail, you may find
# current contact information at www.novell.com.
# ------------------------------------------------------------------------------

require "yast"
require "cwm/widget"

Yast.import "Language"

module Y2Packager
  module Widgets
    # Language selection widget
    #
    # In contrast to {Y2Packager::Widgets::LanguageSelection}, this modules does not
    # modify the system language in any way.
    class SimpleLanguageSelection < CWM::ComboBox
      # @return [String] Default language code
      attr_reader :default
      # @return [String] List of languages to display (en_US, de_DE, etc.)
      attr_reader :languages

      # @param languages [Array<String>] List of languages to display (en_US, de_DE, etc.)
      # @param default   [String]        Default language code
      def initialize(languages, default)
        textdomain "packager"
        @languages = languages
        @default = default
        self.widget_id = "simple_language_selection"
      end

      # Widget label
      #
      # @return [String]
      def label
        _("&Language")
      end

      # Widget options
      #
      # Widget is forced to report immediatelly after value changed.
      def opt
        opts = [:notify]
        opts << :disabled unless items.size > 1
        opts
      end

      # [String] Default license language.
      DEFAULT_LICENSE_LANG = "en_US".freeze

      # Initialize to the given default language
      #
      # If the language is not in the list of options, it will try with the
      # short code (for instance, "de" for "de_DE"). If it fails again, its
      # initial value will be set to "en_US".
      def init
        languages = items.map(&:first)
        new_value =
          if languages.include?(default)
            default
          elsif default.include?("_")    # LC#generalize ???
            short_code = default.split("_").first
            languages.include?(short_code) ? short_code : nil
          end

        self.value = new_value || DEFAULT_LICENSE_LANG
      end

      # Widget help text
      #
      # @return [String]
      def help
        ""
      end

      # Return the options to be shown in the combobox
      #
      # @return [Array<Array<String,String>>] Array of languages in form [code, description]
      def items
        return @items if @items
        lmap = Yast::Language.GetLanguagesMap(false)
        @items = languages.map do |lang|
          [lang, LanguageTag.new(lang).name(lang_map_cache: lmap)]
        end
        @items.reject! { |_lang, name| name.nil? }
        @items.uniq!
        @items.sort_by!(&:last)
      end
    end

    # {::Comparable} enforces a total ordering, contrary to its
    # documentation, WTF.
    module PartiallyComparable
      def <(other)
        cmp = self.<=>(other)
        return nil if cmp.nil?
        cmp < 0
      end

      def >(other)
        cmp = self.<=>(other)
        return nil if cmp.nil?
        cmp > 0
      end
    end

    # Language tags like "cs" "cs_CZ" "cs_CZ.UTF-8".
    #
    # FIXME: improve the simplistic string comparisons
    class LanguageTag
      include Yast::Logger

      # @param s [String]
      def initialize(s)
        @tag = s
      end

      def to_s
        @tag
      end

      include PartiallyComparable

      # Like with classes (where Special < General) "en_US" < "en"
      # Mnemonics: number of speakers
      def <=>(other)
        return 0 if to_s == other.to_s
        return -1 if to_s.start_with?(other.to_s)
        return 1 if other.to_s.start_with?(to_s)
        nil
      end

      # @return [String,nil]
      def name(lang_map_cache: nil)
        lang_map_cache ||= Yast::Language.GetLanguagesMap(false)
        attrs = lang_map_cache[@tag]
        if attrs.nil?
          # we're en, find en_US
          _tag, attrs = lang_map_cache.find { |k, _v| self > LanguageTag.new(k) }
        end
        if attrs.nil?
          log.warn "Could not find name for language '#{@tag}'"
          return nil
        end

        attrs[4]
      end
    end
  end
end
