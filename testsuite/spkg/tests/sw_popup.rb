# encoding: utf-8

# Test sw_single popups
module Yast
  class SwPopupClient < Client
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


      DUMP("TEST 1: argument .testp -> show popup Versions ...")
      TEST(term(:sw_single, path(".testp")), [@read_map, {}, @exec_map], {})


      DUMP("TEST 2: wrong filename given -> Error reading configuration file")
      TEST(
        term(:sw_single, path(".test"), "dummyfile"),
        [@read_map, {}, @exec_map],
        {}
      )

      @exec_map = { "target" => { "bash" => 1 } }

      DUMP("TEST 3: wrong rpm-filename given -> File not found")
      TEST(
        term(:sw_single, path(".test"), "dummyfile.rpm"),
        [@read_map, {}, @exec_map],
        {}
      )


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
        "yast2"  => { "instsource" => { "cdnum" => 2, "cdrelease" => 1234 } },
        "probe"  => {
          "cdrom"        => [{ "dev_name" => "/dev/sr0" }],
          "architecture" => "i386"
        },
        "target" => { "root" => "/" }
      }

      DUMP("TEST 4: CD number is set to 2 -> popup Please insert CD 2")
      TEST(term(:sw_single, path(".test")), [@read_map, {}, @exec_map], {})

      DUMP(
        "TEST 5: CD number is set to 2 and argument beginner -> show popup No access to ..."
      )
      TEST(
        term(:sw_single, path(".test"), "beginner"),
        [@read_map, {}, @exec_map],
        {}
      )

      nil
    end
  end
end

Yast::SwPopupClient.new.main
