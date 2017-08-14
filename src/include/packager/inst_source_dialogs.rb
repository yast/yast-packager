# encoding: utf-8

# File:		inst_source_dialogs.ycp
#
# Authors:		Klaus Kaempf <kkaempf@suse.de>
#			Gabriele Strattner <gs@suse.de>
#			Stefan Schubert <schubi@suse.de>
#                      Cornelius Schumacher <cschum@suse.de>
#
# Purpose:
# Displays possibilities to install from NFS, CD or partion
# Do the "mount" for testing the input.
#
# $Id$
module Yast
  module PackagerInstSourceDialogsInclude
    def initialize_packager_inst_source_dialogs(_include_target)
      textdomain "packager"

      Yast.import "Label"
      Yast.import "URL"
      Yast.import "SourceDialogs"
    end

    def editUrl2(url, allowHttps)
      allowHttps ?
        SourceDialogs.EditPopup(url) :
        SourceDialogs.EditPopupNoHTTPS(url)
    end

    def editUrl(url)
      SourceDialogs.EditPopup(url)
    end
  end
end
