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

require "yast"

require "cwm"

module Installation
  module Console
    module Plugins
      # define a CWM widget for starting repository configuration
      class RepositoriesButton < CWM::PushButton
        def initialize
          textdomain "packager"
        end

        def label
          # TRANSLATORS: a button label, it starts the repository configuration
          _("Configure Software Repositories...")
        end

        def help
          # TRANSLATORS: help text
          _("<p>If you need to use an additional repository for installing packages " \
            "then use the <b>Configure Software Repositories</b> button.</p>")
        end

        def handle
          Yast::WFM.call("repositories")
          nil
        end
      end

      # define a console plugin
      class RepositoriesButtonPlugin < MenuPlugin
        def widget
          RepositoriesButton.new
        end
      end
    end
  end
end
