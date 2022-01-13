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

stub_module("Language")
stub_module("Proxy")
stub_module("FTP")
stub_module("HTTP")
stub_module("NtpClient")
stub_module("InstFunctions")

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
