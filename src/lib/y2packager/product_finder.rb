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
    # @param base [String] The name of the base product used for evaluating the
    #  dependencies.
    #
    # @return [Array<Hash>] The list of found products
    #
    def products(base = nil)
      marked_base_products = base_product_tags
      # evaluate all products
      pool.whatprovides(pool.str2id("product()")).each_with_object([]) do |s, list|
        # the dependant repositories, includes also the transient dependencies
        required = []
        solver = pool.Solver
        # select this product solvable (the product *-release package)
        jobs = [pool.Job(Solv::Job::SOLVER_SOLVABLE | Solv::Job::SOLVER_INSTALL, s.id)]

        if base
          # select the base product
          base_product = pool.select("product(#{base})", Solv::Selection::SELECTION_PROVIDES)
          jobs += base_product.jobs(Solv::Job::SOLVER_INSTALL)
        end

        # run the solver to evaluate all dependencies
        problems = solver.solve(jobs)

        # in case of problems, ignore the dependencies
        if problems.empty?
          # find all repositories which have a product selected to install
          solver.transaction.newsolvables.each do |n|
            next if n == s
            n.lookup_deparray(Solv::SOLVABLE_PROVIDES).each do |dep|
              next unless dep.str.start_with?("product(")
              required << n.repo.name
            end
          end

          required.uniq!
          required.sort!
        end

        ret = {
          prod_dir:        s.repo.name,
          product_package: s.name,
          summary:         s.lookup_str(Solv::SOLVABLE_SUMMARY),
          description:     s.lookup_str(Solv::SOLVABLE_DESCRIPTION),
          depends_on:      problems.empty? ? required : nil,
          order:           display_order(s)
        }

        # in theory a release package might provide several products,
        # create an item for each of them
        s.lookup_deparray(Solv::SOLVABLE_PROVIDES).each do |p|
          next unless p.str =~ /\Aproduct\(\)\s*=\s*(\S+)/
          product_name = Regexp.last_match[1]
          product_data = {
            product_name: product_name,
            base:         marked_base_products.include?(product_name)
          }

          list << ret.merge(product_data)
        end
      end
    end

  private

    #
    # Return the list of marked base products. A base product is defined
    # by the "system-installation() = <product>" provides.
    #
    # @return [Array<String>] The base products
    #
    def base_product_tags
      install_provides = pool.whatprovides(pool.str2id("system-installation()"))

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
        order = Regexp.last_match[1].to_i if Regexp.last_match
      end

      order
    end

    attr_reader :pool
  end
end
