# Copyright (c) [2021] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "y2packager/product_spec"

Yast.import "Packages"
Yast.import "InstURL"
Yast.import "Pkg"
Yast.import "AddOnProduct"
Yast.import "WorkflowManager"

module Y2Packager
  # Describes a product that comes from an installation medium with multiple
  # repositories
  #
  # These products are available in the installation media, in a dedicated
  # directory each one.
  class RepoProductSpec < ProductSpec
    # @return [Array<String>,nil] The product dependencies, includes also the transitive
    #  (indirect) dependencies, if the dependencies cannot be evaluated
    #  (e.g. because of conflicts) then the value is `nil`
    attr_reader :depends_on

    # @return [String] Path on the medium (relative to the medium root)
    attr_reader :dir

    attr_reader :media_name

    # @return [String,nil] Product description
    attr_reader :description

    def initialize(name:, version:, arch:, display_name:, order:, base:, depends_on:, dir:,
      media_name:, description:)
      super(name: name, version: version, display_name: display_name, arch: arch,
            order: order, base: base)

      @depends_on = depends_on
      @dir = dir
      @media_name = media_name
      @description = description
    end

    # Select the product for installation
    #
    # Sets up the repository, searches for the libzypp product and selects it for installation.
    def select
      super

      # in offline installation add the repository with the selected base product
      show_popup = true
      base_url = Yast::InstURL.installInf2Url("")
      log_url = Yast::URL.HidePassword(base_url)
      Yast::Packages.Initialize_StageInitial(show_popup, base_url, log_url, dir)
      # select the product to install
      to_product.select
      # initialize addons and the workflow manager
      Yast::AddOnProduct.SetBaseProductURL(base_url)
      Yast::WorkflowManager.SetBaseWorkflow(false)
    end
  end
end