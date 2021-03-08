# ------------------------------------------------------------------------------
# Copyright (c) 2021 SUSE LLC, All Rights Reserved.
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

require "pp"
require "yast"

module Installation
  module Console
    # define the "repositories" command in the expert console
    class Commands
      def repositories
        Yast.import "Pkg"

        repos = Yast::Pkg.SourceGetCurrent(false).map do |repo|
          Yast::Pkg.SourceGeneralData(repo)
        end

        pp repos
      end

    private

      def repositories_description
        "Dump the details of the currently defined software repositories"
      end
    end
  end
end
