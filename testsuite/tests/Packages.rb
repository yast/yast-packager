# encoding: utf-8

# Testsuite for Packages.ycp module
#
module Yast
  class PackagesClient < Client
    def main
      Yast.include self, "testsuite.rb"

      # huh, we need to mock too much paths because of some module constructor... :-(
      @READ = {
        "target"    => {
          "tmpdir" => "/tmp",
          "size"   => 1,
          "stat"   => { "isreg" => true }
        },
        "xml"       => {},
        "sysconfig" => {
          "language" => {
            "RC_LANG"             => "en_US.UTF-8",
            "ROOT_USES_LANG"      => "ctype",
            "RC_LANG"             => "en_US.UTF-8",
            "INSTALLED_LANGUAGES" => ""
          },
          "console"  => { "CONSOLE_ENCODING" => "UTF-8" }
        }
      }

      @EXEC = {
        "target" => {
          "bash_output" => { "exit" => 0, "stdout" => "charmap=\"UTF-8\"\n" }
        }
      }

      TESTSUITE_INIT([@READ, {}, @EXEC], nil)

      Yast.import "Packages"



      DUMP(" ----- biosdevname tests ----- ")

      # explicitly enable
      Ops.set(
        @READ,
        ["target", "string"],
        "install=cd:// vga=0x314 biosdevname=1"
      )
      TEST(lambda { Packages.kernelCmdLinePackages }, [@READ, {}, @EXEC], nil)

      # explicitly disable
      Ops.set(
        @READ,
        ["target", "string"],
        "install=cd:// vga=0x314 biosdevname=0"
      )
      TEST(lambda { Packages.kernelCmdLinePackages }, [@READ, {}, @EXEC], nil)


      # autodetection, no biosdevname=0|1 boot option
      Ops.set(@READ, ["target", "string"], "install=cd:// vga=0x314")

      # a Dell system
      Ops.set(
        @EXEC,
        ["target", "bash"],
        0
      )
      TEST(lambda { Packages.kernelCmdLinePackages }, [@READ, {}, @EXEC], nil)

      # a non-Dell system
      Ops.set(
        @EXEC,
        ["target", "bash"],
        1
      )
      TEST(lambda { Packages.kernelCmdLinePackages }, [@READ, {}, @EXEC], nil)

      nil
    end
  end
end

Yast::PackagesClient.new.main
