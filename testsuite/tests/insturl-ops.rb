# encoding: utf-8

module Yast
  class InsturlOpsClient < Client
    def main
      Yast.include self, "testsuite.rb"
      @READ = {
        "target" => { "size" => 1, "tmpdir" => "/tmp" },
        "etc"    => { "install_inf" => { "InstMode" => "cd" } },
        "probe"  => { "cdrom" => [{ "dev_name" => "/dev/hda" }] }
      }

      TESTSUITE_INIT([@READ], nil)
      Yast.import "InstURL"

      TEST(lambda { InstURL.installInf2Url("") }, [@READ], nil)
      Ops.set(
        @READ,
        ["probe", "cdrom"],
        [{ "dev_name" => "/dev/hdb" }, { "dev_name" => "/dev/hdd" }]
      )
      TEST(lambda { InstURL.RewriteCDUrl("cd:///sp2?devices=/dev/hda") }, [@READ], nil)

      nil
    end
  end
end

Yast::InsturlOpsClient.new.main
