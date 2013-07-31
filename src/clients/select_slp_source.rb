# encoding: utf-8

# File:
#  select_slp_source.ycp
#
# Module:
#  Client for selecting SLP repository.
#  The purpose is to make inst_source.ycp independent on yast-slp
#
# Authors:
#  Ladislav Slezák <lslezak@suse.cz>
#
# $Id: $
#
module Yast
  class SelectSlpSourceClient < Client
    def main
      Yast.import "SourceManagerSLP"

      SourceManagerSLP.AddSourceTypeSLP
    end
  end
end

Yast::SelectSlpSourceClient.new.main
