module Yast
  # Checking whether system has enough memory (bugzilla #305554)
  class InstCheckMemsizeClient < Client
    def main
      Yast.include self, "add-on/misc.rb"

      # Memory is low
      if HasInsufficientMemory()
        # User wants to continue
        return ContinueIfInsufficientMemory() ? :continue : :skip
      end

      # Enough memory
      :continue
    end
  end
end

Yast::InstCheckMemsizeClient.new.main
