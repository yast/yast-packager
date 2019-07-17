module Yast
  # Purpose:
  # Displays possibilities to install from NFS, CD or partion
  # Do the "mount" for testing the input.
  module PackagerInstSourceDialogsInclude
    def initialize_packager_inst_source_dialogs(_include_target)
      textdomain "packager"

      Yast.import "Label"
      Yast.import "URL"
      Yast.import "SourceDialogs"
    end

    def editUrl2(url, allow_https)
      allow_https ? SourceDialogs.EditPopup(url) : SourceDialogs.EditPopupNoHTTPS(url)
    end

    def editUrl(url)
      SourceDialogs.EditPopup(url)
    end
  end
end
