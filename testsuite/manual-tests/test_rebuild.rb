# encoding: utf-8

module Yast
  class TestRebuildClient < Client
    def main
      Yast.import "PackageCallbacks"

      PackageCallbacks.StartRebuildDB

      @p = 0
      while Ops.less_than(@p, 100)
        @p = Ops.add(@p, 5)
        PackageCallbacks.ProgressRebuildDB(@p)
        Builtins.sleep(100)
      end

      PackageCallbacks.StopRebuildDB(1, "kernel is on vacation")

      nil
    end
  end
end

Yast::TestRebuildClient.new.main
