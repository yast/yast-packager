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
require "fileutils"
require "y2packager/release_notes_store"
require "y2packager/release_notes_rpm_reader"

Yast.import "Directory"
Yast.import "Pkg"

module Y2Packager
  # This class is able to read release notes for a given product
  #
  # It can use two different strategies or backends:
  #
  # * ReleaseNotesRpmReader which gets release notes from a package.
  # * ReleaseNotesUrlReader which gets release notes from an external URL.
  #   This one is used only when the system is not registered or system
  #   updates have not been enabled.
  #
  # Already downloaded release notes are stored in a cache (ReleaseNotesStore)
  # so they are not downloaded twice.
  class ReleaseNotesReader
    include Yast::Logger

    # Product to get release notes for
    attr_reader :product

    # Constructor
    #
    # @param release_notes_store [ReleaseNotesStore] Release notes store to cache data
    def initialize(product, release_notes_store = nil)
      @release_notes_store = release_notes_store
      @product = product
    end

    # Get release notes for a given product
    #
    # @param user_lang [String]              Release notes language (falling back to "en_US"
    #                                        and "en")
    # @param format    [Symbol]              Release notes format (:txt or :rtf)
    # @return [String,nil] Release notes or nil if release notes were not found
    #   (no package providing release notes or notes not found in the package)
    def release_notes(user_lang: "en_US", format: :txt)
      from_store = release_notes_store.retrieve(
        product.name, user_lang, format, fetcher.latest_version
      )

      if from_store
        log.info "Release notes for #{product.name} were found"
        return from_store
      end

      release_notes = fetcher.release_notes(user_lang: user_lang, format: format)
      if release_notes
        log.info "Release notes for #{product.name} were found"
        release_notes_store.store(release_notes)
      end

      release_notes
    end

  private

    # Object responsible for fetching the release notes
    #
    # @return [ReleaseNotesRpmReader,ReleaseNotesUrlReader]
    #   Object implementing the logic to download the release notes.
    def fetcher
      @fetcher ||= ReleaseNotesRpmReader.new(product)
    end

    # Release notes store
    #
    # This store is used to cache already retrieved release notes.
    #
    # @return [ReleaseNotesStore] Release notes store
    def release_notes_store
      @release_notes_store ||= Y2Packager::ReleaseNotesStore.current
    end
  end
end
