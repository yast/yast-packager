module Yast
  #  Client for searching for and adding SLP repositories.
  #  The purpose is to make yast2-installation independent on yast-slp
  #  as described in bugzilla #238680.
  class AddInstSourceSlptypeClient < Client
    def main
      Yast.import "SourceManager"
      Yast.import "SourceManagerSLP"

      @service = SourceManagerSLP.AddSourceTypeSLP
      if @service.nil?
        Builtins.y2milestone("No service selected, returning back...")

        return :back
      end

      Builtins.y2milestone("Trying to add repository '%1'", @service)
      # add the repository
      @createResult = SourceManager.createSource(@service)
      Builtins.y2milestone("Adding repository result: %1", @createResult)

      :next
    end
  end
end

Yast::AddInstSourceSlptypeClient.new.main
