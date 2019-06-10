# ------------------------------------------------------------------------------
# Copyright (c) 2019 SUSE LLC, All Rights Reserved.
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

  def <=(other)
    cmp = self.<=>(other)
    return nil if cmp.nil?
    cmp <= 0
  end

  def >=(other)
    cmp = self.<=>(other)
    return nil if cmp.nil?
    cmp >= 0
  end

  def ==(other)
    return true if equal?(other) # object identity
    cmp = self.<=>(other)
    return nil if cmp.nil?
    cmp == 0
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

  # A more general tag: "en_US" -> "en" (-> nil)
  # @return [LanguageTag,nil]
  def generalize
    self.class.new(@tag.split("_").first) if @tag.include? "_"
    # else nil
    # FIXME: or self, find out what makes more sense
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
