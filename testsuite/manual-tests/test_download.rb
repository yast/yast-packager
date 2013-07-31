# encoding: utf-8

module Yast
  class TestDownloadClient < Client
    def main
      Yast.import "PackageCallbacks"

      PackageCallbacks.StartDownload(
        "ftp://www.suse.de/pub/SuSE-Linux-4.2/kinternet.rpm",
        "/tmp/YaST-0x0000001/kinternet.rpm"
      )

      @p = 0
      while Ops.less_than(@p, 100)
        @p = Ops.add(@p, 5)
        PackageCallbacks.ProgressDownload(@p, 100000, 100000)
        Builtins.sleep(100)
      end

      PackageCallbacks.DoneDownload(1, "kernel is on vacation")

      nil
    end
  end
end

Yast::TestDownloadClient.new.main
