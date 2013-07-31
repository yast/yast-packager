# encoding: utf-8

# Test ChangeCD
module Yast
  class SwSourceClient < Client
    def main
      Yast.include self, "testsuite.rb"

      @user_settings = {}

      @exec_map = { "target" => { "bash" => 0 } }

      @read_map = {
        "run"    => {
          "df" => [
            {
              "dummy" => "on",
              "free"  => "Available",
              "name"  => "Mounted",
              "prz"   => "Capacity",
              "spec"  => "Filesystem",
              "used"  => "Used",
              "whole" => "1024-blocks"
            },
            {
              "free"  => "144988",
              "name"  => "/",
              "prz"   => "93%",
              "spec"  => "/dev/sda1",
              "used"  => "1733600",
              "whole" => "1981000"
            },
            {
              "free"  => "2124147",
              "name"  => "/usr",
              "prz"   => "66%",
              "spec"  => "/dev/sda3",
              "used"  => "4080331",
              "whole" => "6543449"
            }
          ]
        },
        "yast2"  => { "instsource" => { "cdnum" => 1, "cdrelease" => 1234 } },
        "probe"  => {
          "cdrom"        => [{ "dev_name" => "/dev/sr0" }],
          "architecture" => "i386"
        },
        "target" => { "root" => "/" }
      }

      DUMP("TEST 1: argument beginner -> skip inst_source")
      TEST(
        term(:sw_single, path(".test"), "beginner"),
        [@read_map, {}, @exec_map],
        {}
      )

      DUMP("TEST 2: argument only .test -> inst_source is first module")
      TEST(term(:sw_single, path(".test")), [@read_map, {}, @exec_map], {})

      nil
    end
  end
end

Yast::SwSourceClient.new.main
