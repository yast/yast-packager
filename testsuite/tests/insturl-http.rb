# encoding: utf-8

module Yast
  class InsturlHttpClient < Client
    def main
      Yast.include self, "testsuite.rb"
      @READ = {
        "target" => { "size" => 1, "tmpdir" => "/tmp" },
        "etc"    => {
          "install_inf" => {
            "InstMode"  => "http",
            "Server"    => "192.168.1.1",
            "Serverdir" => "/install"
          }
        }
      }

      TESTSUITE_INIT([@READ], nil)
      Yast.import "InstURL"
      Yast.import "Linuxrc"

      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)
      TEST(lambda { InstURL.installInf2Url("test") }, [@READ], nil)
      TEST(lambda { InstURL.installInf2Url("/test") }, [@READ], nil)



      Ops.set(@READ, ["etc", "install_inf", "Username"], "suse")
      Ops.set(@READ, ["etc", "install_inf", "Password"], "yast2")
      Ops.set(@READ, ["etc", "install_inf", "Serverdir"], "pub")
      Ops.set(@READ, ["etc", "install_inf", "Port"], "8888")
      Linuxrc.ResetInstallInf
      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)

      Ops.set(@READ, ["etc", "install_inf", "Proxy"], "http://proxy.suse.de")
      Ops.set(@READ, ["etc", "install_inf", "ProxyPort"], "8888")
      Ops.set(@READ, ["etc", "install_inf", "ProxyUser"], "foo")
      Ops.set(@READ, ["etc", "install_inf", "ProxyPassword"], "bar")
      Linuxrc.ResetInstallInf
      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)

      nil
    end
  end
end

Yast::InsturlHttpClient.new.main
