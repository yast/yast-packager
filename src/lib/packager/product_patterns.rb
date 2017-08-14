
# ------------------------------------------------------------------------------
# Copyright (c) 2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# ------------------------------------------------------------------------------
#

require "yast"

module Yast
  # Evaluate the default patterns for the currently selected products
  class ProductPatterns
    include Yast::Logger

    attr_reader :src

    # optionally evaluate only the products in the specified repository
    # (by default use all repositories)
    # @param [Integer,nil] src repository id
    def initialize(src: nil)
      Yast.import "Pkg"
      @src = src
    end

    # Find the default patterns for all selected products.
    # @note The package management and the products needs to be initialized and
    #   selected *before* using this method.
    # @return [Array<String>] pattern names
    def names
      @names ||= find
    end

    # Select the default patterns to installation
    # @note The package management and the products needs to be initialized and
    #   selected *before* using this method.
    # @return [Boolean] true if all patterns were successfuly selected,
    #   false otherwise
    def select
      # use map + all? to try installing *all* patterns, plain all? would stop
      # at the first failure
      names.map { |p| Yast::Pkg.ResolvableInstall(p, :pattern) }.all?
    end

  private

    # Find the default patterns for all selected products.
    # @return [Array<String>] pattern names
    def find
      products = Yast::Pkg.ResolvableProperties("", :product, "")
      remove_unselected(products)
      products.map! { |product| product["name"] }
      log.info "Found selected products: #{products}"

      patterns = products.map { |p| product_patterns(p) }.flatten.uniq
      log.info "Default patterns for the selected products: #{patterns.inspect}"

      patterns
    end

    # Find the default patterns for the product.
    # @param [String] product product name
    # @return [Array<String>] pattern names
    def product_patterns(product)
      product_dependencies = dependencies(product)
      product_provides = provides(product_dependencies)

      default_patterns(product_provides)
    end

    # Find dependencies for the product (it's product package).
    # @param [String] product product name
    # @return [Array<Hash>] product dependencies, e.g. [{"provides" => "foo"},
    #   {"requires" => "bar"}, ...]
    def dependencies(product)
      product_dependencies = []

      resolvables = Yast::Pkg.ResolvableProperties(product, :product, "")
      remove_unselected(resolvables)
      remove_other_repos(resolvables) if src

      resolvables.each do |resolvable|
        prod_pkg = resolvable["product_package"]
        next unless prod_pkg

        release_resolvables = Yast::Pkg.ResolvableDependencies(prod_pkg, :package, "")
        remove_unselected(release_resolvables)

        release_resolvables.each do |release_resolvable|
          deps = release_resolvable["deps"]
          product_dependencies.concat(deps) if deps
        end
      end

      log.debug "Product #{product} depependencies: #{product_dependencies}"

      product_dependencies
    end

    # Remove not selected resolvables from the list
    # @param [Array<Hash>] resolvables only the Hashes where the key "status"
    #   maps to :selected value are kept, the rest is removed
    def remove_unselected(resolvables)
      resolvables.select! { |p| p["status"] == :selected }
    end

    # Remove the resolvables from other repositories than in 'src'
    # @param [Array<Hash>] resolvables only the Hashes where the key "status"
    #   is equal to `src` are kept, the rest is removed
    def remove_other_repos(resolvables)
      resolvables.select! { |p| p["source"] == src }
    end

    # Collect "provides" dependencies from the list.
    # @param [Array<Hash>] dependencies all dependencies
    # @return [Array<String>] only the "provides" dependencies
    # @example
    #   provides([{"provides" => "foo"}, {"requires" => "bar"}, ...]) => ["foo"]
    def provides(dependencies)
      provides = []

      dependencies.each do |dependency|
        prov = dependency["provides"]
        provides << prov if prov
      end

      log.debug "Collected provides dependencies: #{provides.inspect}"

      provides
    end

    # Collect default pattern names from the provides list.
    # The default pattern is described by the tag "defaultpattern(foo)"
    # @param [Array<String>] provides the "provides" dependencies
    # @return [Array<String>] the default pattern names, empty if no default
    #   pattern is found
    def default_patterns(provides)
      patterns = []

      provides.each do |provide|
        # is it a defaultpattern() provides?
        if provide =~ /\Adefaultpattern\((.*)\)\z/
          log.info "Found default pattern provide: #{provide}"
          patterns << Regexp.last_match[1].strip
        end
      end

      log.info "Found default patterns: #{patterns.inspect}"

      patterns
    end
  end
end
