srcdir = File.expand_path("../../src", __FILE__)
y2dirs = ENV.fetch("Y2DIR", "").split(":")
ENV["Y2DIR"] = y2dirs.unshift(srcdir).join(":")

# force English locale to avoid failing tests due to translations
# when running in non-English environment
ENV["LC_ALL"] = "en_US.UTF-8"

require "yast"
require "yast/rspec"
require "pathname"

TESTS_PATH = Pathname.new(File.dirname(__FILE__))
FIXTURES_PATH = TESTS_PATH.join("data")

RSpec.configure do |config|
  config.extend Yast::I18n  # available in context/describe
  config.include Yast::I18n # available in it/let/before/...
end

# stub module to prevent its Import
# Useful for modules from different yast packages, to avoid build dependencies
def stub_module(name)
  Yast.const_set name.to_sym, Class.new { def self.fake_method; end }
end

stub_module("Language")
stub_module("Proxy")

# the simplecov configuration is shared with the integration tests in
# the ".simplecov" file at the root, it is automatically loaded at "require"
require "simplecov" if ENV["COVERAGE"]
