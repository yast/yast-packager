# ------------------------------------------------------------------------------
# Copyright (c) 2019 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require "solv"

module Y2Packager
  # This class finds products in a Solv pool
  class ProductFinder
    #
    # Constructor
    #
    # @param pool [Solv::Pool] the pool used for evaluating the products
    #
    def initialize(pool)
      @pool = pool.pool
    end

    #
    # Evaluate all products in the pool and return details about them
    # including the dependencies.
    #
    # @param selected_base [String] The name of the base product used for evaluating the
    #  dependencies.
    #
    # @return [Array<Hash>] The list of found products
    #
    def products(selected_base = nil)
      marked_base_products = base_product_tags
      # evaluate all products
      pool.whatprovides(pool.str2id(PRODUCT_PROVIDES))
          .each_with_object([]) do |product_solvable, list|

        list.concat(create_products(product_solvable, marked_base_products, selected_base))
      end
    end

  private

    # special RPM "Provides" tags
    SYSTEM_INSTALLATION_PROVIDES = "system-installation()".freeze
    PRODUCT_PROVIDES = "product()".freeze

    #
    # Return the list of marked base products. A base product is defined
    # by the "system-installation() = <product>" provides.
    #
    # @return [Array<String>] The base products
    #
    def base_product_tags
      install_provides = pool.whatprovides(pool.str2id(SYSTEM_INSTALLATION_PROVIDES))

      tags = install_provides.each_with_object([]) do |s, list|
        provides = s.lookup_deparray(Solv::SOLVABLE_PROVIDES)

        provides.each do |p|
          next unless p.str =~ /system-installation\(\)\s*=\s*(\S+)/
          list << Regexp.last_match[1]
        end
      end

      tags.uniq
    end

    #
    # Find the "displayorder()" provides value for the specific solvable object
    #
    # @param solvable [Solv] The solvable object from the pool
    #
    # @return [Integer,nil] The display order value or nil if not defined
    #
    def display_order(solvable)
      # all solvable provides
      provides = solvable.lookup_deparray(Solv::SOLVABLE_PROVIDES)

      order = nil
      provides.each do |p|
        next unless p.str =~ /\Adisplayorder\(\s*([0-9]+)\s*\)\z/
        order = Regexp.last_match[1].to_i
      end

      order
    end

    #
    # Evaluate the products
    #
    # @param product_solvable [Solv] the product solvable to create
    # @param found_base_products [Array<String>] the found base products
    # @param selected_base [String,nil] the preferred base product, if nil
    #  the solver might select some base product automatically to satisfy the
    #  dependencies.
    #
    # @return [Array<Hash>] the found products
    #
    def create_products(product_solvable, found_base_products, selected_base)
      ret = []

      data = {
        prod_dir:        product_solvable.repo.name,
        product_package: product_solvable.name,
        summary:         product_solvable.lookup_str(Solv::SOLVABLE_SUMMARY),
        description:     product_solvable.lookup_str(Solv::SOLVABLE_DESCRIPTION),
        depends_on:      find_dependencies(product_solvable, selected_base),
        order:           display_order(product_solvable)
      }

      # in theory a release package might provide several products,
      # create an item for each of them
      product_solvable.lookup_deparray(Solv::SOLVABLE_PROVIDES).each do |p|
        product_name = p.str[/\Aproduct\(\)\s*=\s*(\S+)/, 1]
        next unless product_name

        product_data = {
          product_name: product_name,
          base:         found_base_products.include?(product_name)
        }

        ret << data.merge(product_data)
      end

      ret
    end

    #
    # Create the solver jobs for selecting the products in the pool
    #
    # @param product_solvable [Solv] The product solvable to select
    # @param base [String,nil] Optional base product to select
    #
    # @return [Array<Solv::Job>] The solver jobs
    #
    def select_products(product_solvable, base)
      # select this product solvable (the product *-release package)
      jobs = [pool.Job(Solv::Job::SOLVER_SOLVABLE |
        Solv::Job::SOLVER_INSTALL, product_solvable.id)]

      if base
        # select the base product
        base_product = pool.select("product(#{base})", Solv::Selection::SELECTION_PROVIDES)
        jobs += base_product.jobs(Solv::Job::SOLVER_INSTALL)
      end

      jobs
    end

    #
    # Find dependencies for the product
    #
    # @param product_solvable [Solv] The input product
    # @param selected_base [String,nil] The preferred base product
    #
    # @return [Array<String>] list of the dependant products (repository directories)
    #
    def find_dependencies(product_solvable, selected_base)
      # the dependent repositories, includes also the transient dependencies
      jobs = select_products(product_solvable, selected_base)
      solver = pool.Solver

      # run the solver to evaluate all dependencies
      problems = solver.solve(jobs)

      # if the solver failed we cannot evaluate the dependencies,
      # something is probably missing or there are conflicts
      return nil if !problems.empty?

      ret = []
      # find all repositories which have a product selected to install
      solver.transaction.newsolvables.each do |new_solvable|
        next if new_solvable == product_solvable
        new_solvable.lookup_deparray(Solv::SOLVABLE_PROVIDES).each do |dep|
          next unless dep.str.start_with?("product(")
          ret << new_solvable.repo.name
        end
      end

      ret.uniq!
      ret.sort
    end

    attr_reader :pool
  end
end
