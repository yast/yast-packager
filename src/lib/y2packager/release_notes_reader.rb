require "yast"
require "fileutils"
require "y2packager/package"
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

    # @return [Pathname] Place to store all release notes
    attr_reader :work_dir

    # Constructor
    #
    # @param work_dir [Pathname] Temporal directory to work
    def initialize(work_dir = nil)
      @work_dir = work_dir || Pathname(Yast::Directory.tmpdir).join("release-notes")
    end

    # Get release notes for a given product
    #
    # Release notes are downloaded and extracted to work directory.  When
    # release notes for a language "xx_XX" are not found, it will fallback to
    # "xx".
    #
    # @param product [Y2Packager::Product] Product
    # @param lang    [String]              Release notes language (falling back to "en")
    # @param format  [Symbol]              Release notes format (:txt or :rtf)
    # @return [String,nil] Release notes or nil if a release notes were not found
    #   (no package providing release notes or notes not found in the package)
    def for(product, lang: "en_US", format: :txt)
      package = release_notes_package_for(product)
      return nil if package.nil?
      download_and_extract(package)
      content = release_notes_content(package, lang, format)
      cleanup
      content
    end

  private

    def cleanup
      ::FileUtils.rm_r(work_dir) if work_dir.directory?
    end

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
      Y2Packager::Package.find(package_name).find { |s| s.status == :available }
    end

    # Return release notes content for a package, language and format
    #
    # Release notes are downloaded and extracted to work directory.  When
    # release notes for a language "xx_XX" are not found, it will fallback to
    # "xx".
    #
    # @param package [String] Release notes package name
    # @param lang    [String] Language code ("en_US", "en", etc.)
    # @param format  [Symbol] Content format (:txt, :rtf, etc.).
    # @see release_notes_file
    def release_notes_content(package, lang, format)
      file = release_notes_file(package, lang, format)
      file ? File.read(file) : nil
    end

    FALLBACK_LANGS = ["en_US", "en"].freeze
    # Return release notes file path for a given package, language and format
    #
    # Release notes are downloaded and extracted to work directory.  When
    # release notes for a language "xx_XX" are not found, it will fallback to
    # "xx".
    #
    # @param package [String] Release notes package name
    # @param lang    [String] Language code ("en_US", "en", etc.)
    # @param format  [Symbol] Content format (:txt, :rtf, etc.).
    def release_notes_file(package, lang, format)
      langs = [lang]
      langs << lang[0..1] if lang.size > 2
      langs.concat(FALLBACK_LANGS)

      Dir.glob(
        File.join(
          release_notes_path(package), "**", "RELEASE-NOTES.{#{langs.join(",")}}.#{format}"
        )
      ).first
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
  end
end
