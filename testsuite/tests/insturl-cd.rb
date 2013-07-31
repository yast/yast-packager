# encoding: utf-8

module Yast
  class InsturlCdClient < Client
    def main
      Yast.include self, "testsuite.rb"
      @READ = {
        "target" => { "size" => 1, "tmpdir" => "/tmp" },
        "etc"    => { "install_inf" => { "InstMode" => "cd" } },
        "probe"  => { "cdrom" => [{ "dev_name" => "/dev/hda" }] }
      }

      TESTSUITE_INIT([@READ], nil)
      Yast.import "InstURL"
      Yast.import "Linuxrc"

      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)
      Linuxrc.ResetInstallInf
      Ops.set(@READ, ["etc", "install_inf", "InstMode"], nil)
      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)

      nil
    end
  end
end

Yast::InsturlCdClient.new.main
