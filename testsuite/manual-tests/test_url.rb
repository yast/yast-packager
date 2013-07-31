# encoding: utf-8

module Yast
  class TestUrlClient < Client
    def main
      Yast.import "InstURL"
      Yast.import "URL"

      @url = InstURL.installInf2Url("")
      @log_url = URL.HidePassword(@url)
      Builtins.y2milestone("URL %1", @url)

      nil
    end
  end
end

Yast::TestUrlClient.new.main
