module Yast
  #  Client for selecting SLP repository.
  #  The purpose is to make inst_source.ycp independent on yast-slp
  class SelectSlpSourceClient < Client
    def main
      Yast.import "SourceManagerSLP"

      SourceManagerSLP.AddSourceTypeSLP
    end
  end
end

Yast::SelectSlpSourceClient.new.main
