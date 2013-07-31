# encoding: utf-8

module Yast
  class InstallInf2UrlClient < Client
    def main
      Yast.import "InstURL"

      @extradir1 = ""
      @extradir2 = "extradir"
      @extradir3 = "/extradir"

      @url1 = InstURL.installInf2Url(@extradir1)
      @url2 = InstURL.installInf2Url(@extradir2)
      @url3 = InstURL.installInf2Url(@extradir3)

      [@url1, @url2, @url3]
    end
  end
end

Yast::InstallInf2UrlClient.new.main
