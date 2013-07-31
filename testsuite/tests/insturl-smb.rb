# encoding: utf-8

module Yast
  class InsturlSmbClient < Client
    def main
      Yast.include self, "testsuite.rb"
      @READ = {
        "target" => { "size" => 1, "tmpdir" => "/tmp" },
        "etc"    => {
          "install_inf" => {
            "InstMode"  => "smb",
            "Server"    => "192.168.1.1",
            "Serverdir" => "pub",
            "Share"     => "SHARE"
          }
        }
      }

      TESTSUITE_INIT([@READ], nil)
      Yast.import "InstURL"
      Yast.import "Linuxrc"

      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)
      TEST(lambda { InstURL.installInf2Url("test") }, [@READ], nil)
      TEST(lambda { InstURL.installInf2Url("/test") }, [@READ], nil)


      Ops.set(@READ, ["etc", "install_inf", "Serverdir"], "/pub")
      Linuxrc.ResetInstallInf
      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)

      Ops.set(@READ, ["etc", "install_inf", "Username"], "suse")
      Ops.set(@READ, ["etc", "install_inf", "Password"], "yast2")
      Ops.set(@READ, ["etc", "install_inf", "Serverdir"], "pub")
      Linuxrc.ResetInstallInf
      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)

      Ops.set(@READ, ["etc", "install_inf", "WorkDomain"], "group")
      Linuxrc.ResetInstallInf
      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)

      nil
    end
  end
end

Yast::InsturlSmbClient.new.main
