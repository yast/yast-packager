# encoding: utf-8

module Yast
  class TestCallbacksClient < Client
    def main
      Yast.import "PackageCallbacks"

      PackageCallbacks.StartProvide("package", 10000, true)
      @i = 0
      while Ops.less_than(@i, 100)
        Builtins.sleep(10)
        PackageCallbacks.ProgressProvide(@i)
        @i = Ops.add(@i, 1)
      end
      PackageCallbacks.DoneProvide(0, "", "")

      nil
    end
  end
end

Yast::TestCallbacksClient.new.main
