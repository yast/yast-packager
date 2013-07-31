# encoding: utf-8

module Yast
  class InsturlIsoClient < Client
    def main
      Yast.include self, "testsuite.rb"
      @READ = {
        "target" => { "size" => 1, "tmpdir" => "/tmp" },
        "etc"    => {
          "install_inf" => {
            "InstMode"   => "nfs",
            "Server"     => "192.168.1.1",
            "Serverdir"  => "/install/images/CD1.iso",
            "SourceType" => "file"
          }
        }
      }

      TESTSUITE_INIT([@READ], nil)
      Yast.import "InstURL"
      Yast.import "Linuxrc"

      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)
      TEST(lambda { InstURL.installInf2Url("test") }, [@READ], nil)
      TEST(lambda { InstURL.installInf2Url("/test") }, [@READ], nil)

      nil
    end
  end
end

Yast::InsturlIsoClient.new.main
