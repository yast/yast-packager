# Copyright (c) 2018 SUSE LLC
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

Yast.import "Pkg"

module Y2Packager
  # filter the packages from a self-update repository which should be
  # used as an add-on instead of applying into the inst-sys
  class SelfUpdateAddonFilter
    extend Yast::Logger

    PROVIDES_INSTALLATION = "system-installation()".freeze
    PROVIDES_PRODUCT = "product()".freeze

    #
    # Returns package name from the selected repository which should be used
    # in an update repository instead of applying to the ins-sys.
    #
    # @param repo_id [Integer] the self-update repository ID
    # @return [Array<String>] the list of packages which should be used
    #   in an addon repository
    #
    def self.packages(repo_id)
      # returns list like [["skelcd-control-SLED", :CAND, :NONE],
      # ["skelcd-control-SLES", :CAND, :NONE],...]
      package_data = Yast::Pkg.PkgQueryProvides(PROVIDES_INSTALLATION) +
        Yast::Pkg.PkgQueryProvides(PROVIDES_PRODUCT)

      pkgs = package_data.map(&:first).uniq

      # there should not be present any other repository except the self update at this point,
      # but rather be safe than sorry...

      pkgs.select! do |pkg|
        props = Yast::Pkg.ResolvableProperties(pkg, :package, "")
        props.any? { |p| p["source"] == repo_id }
      end

      log.info "Found addon packages in the self update repository: #{pkgs}"

      pkgs
    end
  end
end
