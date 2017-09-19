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
require "y2packager/release_notes"
require "packages/package_downloader"
require "tmpdir"

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
  class ReleaseNotesRpmReader
    include Yast::Logger

    # @return [Product] Product to get release notes for
    attr_reader :product

    # Constructor
    #
    # @param product [Product] Product to get release notes for
    def initialize(product)
      @product = product
    end

    # Get release notes for the given product
    #
    # Release notes are downloaded and extracted to work directory.  When
    # release notes for a language "xx_XX" are not found, it will fallback to
    # "xx".
    #
    # @param user_lang     [String] User preferred language (falling back to fallback_lang)
    # @param format        [Symbol] Release notes format (:txt or :rtf)
    # @param fallback_lang [String] Release notes fallback language
    # @return [String,nil] Release notes or nil if a release notes were not found
    #   (no package providing release notes or notes not found in the package)
    def release_notes(user_lang: "en_US", format: :txt, fallback_lang: "en")
      if release_notes_package.nil?
        log.info "No package containing release notes for #{product.name} was found"
        return nil
      end

      extract_release_notes(user_lang, format, fallback_lang)
    end

    # Return release notes latest version
    #
    # @return [String] Package version
    def latest_version
      return :none if release_notes_package.nil?
      release_notes_package.version
    end

  private

    # Return the release notes package for a given product
    #
    # This method queries libzypp asking for the package which contains release
    # notes for the given product. It relies on the `release-notes()` tag.
    #
    # @return [Package,nil] Package containing the release notes; nil if not found
    def release_notes_package
      return @release_notes_package if @release_notes_package
      provides = Yast::Pkg.PkgQueryProvides("release-notes()")
      release_notes_packages = provides.map(&:first).uniq
      package_name = release_notes_packages.find do |name|
        dependencies = Yast::Pkg.ResolvableDependencies(name, :package, "").first["deps"]
        dependencies.any? do |dep|
          dep["provides"].to_s.match(/release-notes\(\)\s*=\s*#{product.name}\s*/)
        end
      end
      return nil if package_name.nil?

      @release_notes_package = find_package(package_name)
    end

    # Valid statuses for packages containing release notes
    AVAILABLE_STATUSES = [:available, :selected].freeze

    # Find the latest available/selected package containing release notes
    #
    # @return [Package,nil] Package containing release notes; nil if not found
    def find_package(name)
      Y2Packager::Package
        .find(name)
        .select { |i| AVAILABLE_STATUSES.include?(i.status) }
        .sort_by { |i| Gem::Version.new(i.version) }
        .last
    end

    # Return release notes instance
    #
    # @param package       [Package] Package containing release notes
    # @param user_lang     [String]  User preferred language (falling back to fallback_lang)
    # @param format        [Symbol]  Release notes format
    # @param fallback_lang [String]  Release notes fallback language
    # @return [ReleaseNotes] Release notes for given arguments
    def extract_release_notes(user_lang, format, fallback_lang)
      content, lang = release_notes_content(
        release_notes_package, user_lang, format, fallback_lang
      )
      return nil if content.nil?

      Y2Packager::ReleaseNotes.new(
        product_name: product.name,
        content:      content,
        user_lang:    user_lang,
        lang:         lang,
        format:       format,
        version:      release_notes_package.version
      )
    end

    # Return release notes content for a package, language and format
    #
    # Release notes are downloaded and extracted to work directory.  When
    # release notes for a language "xx_XX" are not found, it will fallback to
    # "xx".
    #
    # @param package       [String] Release notes package name
    # @param user_lang     [String] User preferred language (falling back to fallback_lang)
    # @param format        [Symbol] Content format (:txt, :rtf, etc.).
    # @param fallback_lang [String] Release notes fallback language
    # @return [Array<String,String>] Array containing content and language code
    # @see release_notes_file
    def release_notes_content(package, user_lang, format, fallback_lang)
      tmpdir = Dir.mktmpdir
      begin
        package.extract_to(tmpdir)
        file, lang = release_notes_file(tmpdir, user_lang, format, fallback_lang)
        file ? [File.read(file), lang] : nil
      ensure
        FileUtils.remove_entry_secure(tmpdir)
      end
    end

    # Return release notes file path for a given package, language and format
    #
    # Release notes are downloaded and extracted to work directory.  When
    # release notes for a language "xx_XX" are not found, it will fallback to
    # "xx".
    #
    # @param directory     [String] Directory where release notes were uncompressed
    # @param user_lang     [String] User preferred language (falling back to fallback_lang)
    # @param format        [Symbol] Content format (:txt, :rtf, etc.)
    # @param fallback_lang [String] Release notes fallback language
    # @return [Array<String,String>] Array containing path and language code
    def release_notes_file(directory, user_lang, format, fallback_lang)
      langs = [user_lang]
      langs << user_lang.split("_", 2).first if user_lang.include?("_")
      langs << fallback_lang

      path = Dir.glob(
        File.join(directory, "**", "RELEASE-NOTES.{#{langs.join(",")}}.#{format}")
      ).first
      return nil if path.nil?
      [path, path[/RELEASE-NOTES\.(.+)\.#{format}\z/, 1]] if path
    end
  end
end
