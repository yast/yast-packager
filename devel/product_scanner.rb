#! /usr/bin/env ruby

# This is a testing script which runs the product scanner
# for the SLES Packages DVD or the Offline installation medium.

require "pp"
require "yast"

# YaST modifies the load path, we need to update it
# *after* calling require "yast"
$LOAD_PATH.unshift(File.join(__dir__, "../src/lib"))

require "y2packager/product_spec_readers/full"

url = ARGV[0]

# if nil (not set) the solver might randomly pick one base product
# to satisfy the dependencies
base_product = ARGV[1]

if url.nil?
  warn "Usage: #{$PROGRAM_NAME} <URL> [base_product]"
  warn "Example: #{$PROGRAM_NAME} \"dir://path/to/media\" SLES"
  warn "Example: #{$PROGRAM_NAME} \"iso:/?iso=DVD.iso&url=dir://path/to/media\" "\
       "(requires root permissions for mounting)"
  warn "See \"Supported URI formats\" section in \"man zypper\"."
  exit 1
end

puts "Scanning #{url}..."

pp Y2Packager::ProductSpecReaders::Full.new.products(url, base_product)
