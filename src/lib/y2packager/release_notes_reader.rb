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
require "y2packager/package"
require "y2packager/release_notes_store"
require "y2packager/release_notes"
require "packages/package_downloader"
require "pathname"

Yast.import "Directory"
Yast.import "Pkg"

module Y2Packager
  # This class is able to read release notes for a given product
  #
  # Release notes for a product are available in a specific package which provides
  # "release-notes()" for the given product. For instance, a package which provides
  # "release-notes() = SLES" will provide release notes for the SLES product.
  #
  # This reader takes care of downloading the release notes package (if any),
  # extracting its content and returning release notes for a given language/format.
  class ReleaseNotesReader
    include Yast::Logger

    # @return [Pathname] Place to store all release notes.
    attr_reader :work_dir

    # Constructor
    #
    # @param work_dir [Pathname,nil] Temporal directory to work. If `nil` it will
    #   use the default YaST temporary directory + "/release-notes".
    # @param release_notes_store [ReleaseNotesStore] Release notes store to cache data
    def initialize(work_dir = nil, release_notes_store = nil)
      @work_dir = work_dir || Pathname(Yast::Directory.tmpdir).join("release-notes")
      @release_notes_store = release_notes_store
    end

    # Get release notes for a given product
    #
    # Release notes are downloaded and extracted to work directory.  When
    # release notes for a language "xx_XX" are not found, it will fallback to
    # "xx".
    #
    # @param product   [Y2Packager::Product] Product
    # @param user_lang [String]              Release notes language (falling back to "en_US"
    #                                        and "en")
    # @param format    [Symbol]              Release notes format (:txt or :rtf)
    # @return [String,nil] Release notes or nil if a release notes were not found
    #   (no package providing release notes or notes not found in the package)
    def release_notes_for(product, user_lang: "en_US", format: :txt)
      package = release_notes_package_for(product)
      return nil if package.nil?

      from_store = release_notes_store.retrieve(product.name, user_lang, format, package.version)
      return from_store if from_store

      release_notes = build_release_notes(product, package, user_lang, format)
      release_notes_store.store(release_notes) if release_notes
      release_notes
    end

  private

    # Clean-up working directory
    def cleanup
      ::FileUtils.rm_r(work_dir) if work_dir.directory?
    end

    AVAILABLE_STATUSES = [:available, :selected].freeze
    # Return the release notes package for a given product
    #
    # This method queries libzypp asking for the package which contains release
    # notes for the given product. It relies on the `release-notes()` tag.
    #
    # @param product [Product] Product
    # @return [Package,nil] Package containing the release notes; nil if not found
    def release_notes_package_for(product)
      provides = Yast::Pkg.PkgQueryProvides("release-notes()")
      release_notes_packages = provides.map(&:first).uniq
      package_name = release_notes_packages.find do |name|
        dependencies = Yast::Pkg.ResolvableDependencies(name, :package, "").first["deps"]
        dependencies.any? do |dep|
          dep["provides"].to_s.match(/release-notes\(\)\s*=\s*#{product.name}\s*/)
        end
      end
      return nil if package_name.nil?
      # FIXME: make sure we get the latest version
      Y2Packager::Package.find(package_name).find { |s| AVAILABLE_STATUSES.include?(s.status) }
    end

    # Return release notes content for a package, language and format
    #
    # Release notes are downloaded and extracted to work directory.  When
    # release notes for a language "xx_XX" are not found, it will fallback to
    # "xx".
    #
    # @param package   [String] Release notes package name
    # @param user_lang [String] Language code ("en_US", "en", etc.)
    # @param format    [Symbol] Content format (:txt, :rtf, etc.).
    # @return [Array<String,String>] Array containing content and language code
    # @see release_notes_file
    def release_notes_content(package, user_lang, format)
      download_and_extract(package)
      file, lang = release_notes_file(package, user_lang, format)
      content = file ? [File.read(file), lang] : nil
      cleanup
      content
    end

    FALLBACK_LANGS = ["en_US", "en"].freeze
    # Return release notes file path for a given package, language and format
    #
    # Release notes are downloaded and extracted to work directory.  When
    # release notes for a language "xx_XX" are not found, it will fallback to
    # "xx".
    #
    # @param package   [String] Release notes package name
    # @param user_lang [String] Language code ("en_US", "en", etc.)
    # @param format    [Symbol] Content format (:txt, :rtf, etc.).
    # @return [Array<String,String>] Array containing path and language code
    def release_notes_file(package, user_lang, format)
      langs = [user_lang]
      langs << user_lang.split("_", 2).first if user_lang.include?("_")
      langs.concat(FALLBACK_LANGS)

      path = Dir.glob(
        File.join(
          release_notes_path(package), "**", "RELEASE-NOTES.{#{langs.join(",")}}.#{format}"
        )
      ).first
      return nil if path.nil?
      [path, path[/RELEASE-NOTES\.(.+)\.#{format}\z/, 1]] if path
    end

    # Download and extract package
    #
    # @return [Boolean]
    def download_and_extract(package)
      target = release_notes_path(package)
      return true if ::File.directory?(target)
      ::FileUtils.mkdir_p(target)
      package.extract_to(target)
    end

    # Return the location of the extracted release notes package
    #
    # @param [Package] Release notes package
    # @return [String] Path to extracted release notes
    def release_notes_path(package)
      work_dir.join(package.name)
    end

    # Return release notes instance
    #
    # @param product   [Product] Product
    # @param package   [Package] Package containing release notes
    # @param user_lang [String]  User preferred language
    # @param format    [Symbol]  Release notes format
    # @return [ReleaseNotes] Release notes for given arguments
    def build_release_notes(product, package, user_lang, format)
      content, lang = release_notes_content(package, user_lang, format)
      return nil if content.nil?
      Y2Packager::ReleaseNotes.new(
        product_name: product.name,
        content:      content,
        user_lang:    user_lang,
        lang:         lang,
        format:       format,
        version:      package.version
      )
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
