
SimpleCov.start do
  # uncomment these lines to track the complete YaST
  # filters.clear
  # add_filter "/usr/lib64/ruby/"
  # add_filter "/usr/lib/ruby/"
  add_filter "/test/"
  add_filter "/features/"
end

# track all ruby files under src
srcdir = File.expand_path("../src", __FILE__)
SimpleCov.track_files("#{srcdir}/**/*.rb")

# uncomment this line to track the complete YaST
# SimpleCov.track_files("/usr/share/YaST2/**/*.rb")

# use coveralls for on-line code coverage reporting at Travis CI
if ENV["TRAVIS"]
  require "coveralls"
  SimpleCov.formatters = [
    SimpleCov::Formatter::HTMLFormatter,
    Coveralls::SimpleCov::Formatter
  ]
end
