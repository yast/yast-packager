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

module Installation
  module Console
    # define the "configure_repositories" command in the expert console
    class Commands
      def configure_repositories
        run_yast_module("repositories")
      end

    private

      def configure_repositories_description
        "Run the repository manager. Be careful when using it,\n" \
          "you might easily break the installer when wrongly used!"
      end
    end
  end
end
