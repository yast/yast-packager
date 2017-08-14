# encoding: utf-8

# File:	clients/inst_check_memsize.ycp
# Package:	Installation
# Summary:	Checking whether system has enough memory (bugzilla #305554)
# Authors:	Lukas Ocilka <locilka@suse.cz>
#
# $Id$
#
module Yast
  class InstCheckMemsizeClient < Client
    def main
      Yast.include self, "add-on/misc.rb"

      # Memory is low
      if HasInsufficientMemory()
        # User wants to continue
        if ContinueIfInsufficientMemory()
          return :continue
          # User wants to skip
        else
          return :skip
        end
      end

      # Enough memory
      :continue
    end
  end
end

Yast::InstCheckMemsizeClient.new.main
