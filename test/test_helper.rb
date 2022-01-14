srcdir = File.expand_path("../src", __dir__)
y2dirs = ENV.fetch("Y2DIR", "").split(":")
ENV["Y2DIR"] = y2dirs.unshift(srcdir).join(":")

# force English locale to avoid failing tests due to translations
# when running in non-English environment
ENV["LC_ALL"] = "en_US.UTF-8"

require "yast"
require "yast/rspec"
require "pathname"

TESTS_PATH = Pathname.new(File.dirname(__FILE__))
DATA_PATH = TESTS_PATH.join("data")

SCR_BASH_PATH = Yast::Path.new(".target.bash")

RSpec.configure do |config|
  config.extend Yast::I18n  # available in context/describe
  config.include Yast::I18n # available in it/let/before/...

  config.mock_with :rspec do |c|
    # https://relishapp.com/rspec/rspec-mocks/v/3-0/docs/verifying-doubles/partial-doubles
    c.verify_partial_doubles = true
  end
end

RSpec::Matchers.define :array_not_including do |x|
  match do |actual|
    return false unless actual.is_a?(Array)

    !actual.include?(x)
  end
end

# stub module to prevent its Import
# Useful for modules from different yast packages, to avoid build dependencies
def stub_module(name)
  Yast.const_set(name.to_sym, Class.new { def self.fake_method; end })
end

# these are not used in the tests so we can just use an empty implementation
stub_module("Proxy")
stub_module("FTP")
stub_module("HTTP")
stub_module("NtpClient")

# helper for defining missing YaST modules
def define_if_missing(name, &block)
  # try loading the module, it might be present in the system (running locally
  # or in GitHub Actions), mock it only when missing (e.g. in OBS build)
  Yast.import name
  puts "Found module Yast::#{name}"
rescue NameError
  warn "Mocking the Yast::#{name} module completely"
  block.call
end

# define missing modules with an API, these are used in the tests and need to
# implement the *same* API as the real modules

define_if_missing("InstFunctions") do
  # see modules/InstFunctions.rb in yast2-installation
  module Yast
    class InstFunctionsClass < Module
      # @return [Boolean]
      def second_stage_required?; end
    end

    InstFunctions = InstFunctionsClass.new
  end
end

define_if_missing("Language") do
  # see modules/Language.rb in yast2-country
  module Yast
    class LanguageClass < Module
      # @return [String]
      def language; end

      # @param _lang [String]
      # @return [Boolean]
      def supported_language?(_lang); end

      # @param _force [Boolean]
      # @return [Hash<String,Array>]
      def GetLanguagesMap(_force); end
    end

    Language = LanguageClass.new
  end
end

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
  end

  # track all ruby files under src
  SimpleCov.track_files("#{srcdir}/**/*.rb")

  # additionally use the LCOV format for on-line code coverage reporting at CI
  if ENV["CI"] || ENV["COVERAGE_LCOV"]
    require "simplecov-lcov"

    SimpleCov::Formatter::LcovFormatter.config do |c|
      c.report_with_single_file = true
      # this is the default Coveralls GitHub Action location
      # https://github.com/marketplace/actions/coveralls-github-action
      c.single_report_path = "coverage/lcov.info"
    end

    SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::LcovFormatter
    ]
  end
end

# mock empty class to avoid build dependency on yast2-installation
module Installation
  module Console
    module Plugins
      class MenuPlugin
        def inspect
          "Stubbed MenuPlugin from tests"
        end
      end
    end
  end
end
