# encoding: utf-8

module Yast
  class TestConvertClient < Client
    def main
      Yast.import "PackageCallbacks"

      PackageCallbacks.StartConvertDB("/path/old")

      @p = 0
      while Ops.less_than(@p, 100)
        @p = Ops.add(@p, 5)
        PackageCallbacks.ProgressConvertDB(42, "/path/old")
        Builtins.sleep(100)
      end

      PackageCallbacks.StopConvertDB(1, "kernel is on vacation")

      nil
    end
  end
end

Yast::TestConvertClient.new.main
