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
require "y2packager/control_product_spec"

Yast.import "Arch"
Yast.import "Linuxrc"
Yast.import "ProductFeatures"

module Y2Packager
  module ProductSpecReaders
    # Reads product specifications from the control file
    class Control
      include Yast::Logger

      # map the Arch.architecture to the arch expected by SCC
      REG_ARCH = {
        "s390_32" => "s390",
        "s390_64" => "s390x",
        # ppc64le is the only supported PPC arch, we do not have to distinguish the BE/LE variants
        "ppc64"   => "ppc64le"
      }.freeze

      def products
        control_products = Yast::ProductFeatures.GetFeature("software", "base_products")

        if !control_products.is_a?(Array)
          log.warn("Invalid or missing 'software/base_products' value: #{control_products.inspect}")
          @products = []
          return @products
        end

        arch = REG_ARCH[Yast::Arch.architecture] || Yast::Arch.architecture
        linuxrc_products = (Yast::Linuxrc.InstallInf("specialproduct") || "")
          .split(",").map(&:strip)

        @products = control_products.each_with_object([]).each_with_index do |(p, array), idx|
          # a hidden product requested?
          if p["special_product"] && !linuxrc_products.include?(p["name"])
            log.info "Skipping special hidden product #{p["name"]}"
            next
          end

          # compatible arch?
          if p["archs"] && !p["archs"].split(",").map(&:strip).include?(arch)
            log.info "Skipping product #{p["name"]} - not compatible with arch #{arch}"
            next
          end

          array << Y2Packager::ControlProductSpec.new(
            name:            p["name"],
            version:         p["version"],
            arch:            arch,
            display_name:    p["display_name"],
            license_url:     p["license_url"],
            register_target: p["register_target"],
            order:           idx
          )
        end
      end
    end
  end
end
