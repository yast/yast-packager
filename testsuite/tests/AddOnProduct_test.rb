# encoding: utf-8

# Testsuite for Addon.ycp module
#
module Yast
  class AddOnProductTestClient < Client
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

      Yast.import "AddOnProduct"

      @url = "http://example.com/repos/SLES11SP2"

      # invalid input
      TEST(lambda { AddOnProduct.SetRepoUrlAlias(nil, nil, nil) }, [], nil)

      # keep the url untouched
      TEST(lambda { AddOnProduct.SetRepoUrlAlias(@url, "", "") }, [], nil)
      TEST(lambda { AddOnProduct.SetRepoUrlAlias(@url, nil, nil) }, [], nil)

      # set name as alias, alias is empty
      TEST(lambda { AddOnProduct.SetRepoUrlAlias(@url, "", "SLES-11-SP2") }, [], nil)

      # set name as alias, alias is empty
      TEST(lambda { AddOnProduct.SetRepoUrlAlias(@url, "SLES", "SLES-11-SP2") }, [], nil)



      # an alias is already set in URL

      @url = "http://example.com/repos/SLES11SP2?alias=mySLES"

      # keep the url untouched
      TEST(lambda { AddOnProduct.SetRepoUrlAlias(@url, "", "") }, [], nil)

      # keep the original alias
      TEST(lambda { AddOnProduct.SetRepoUrlAlias(@url, "", "SLES-11-SP2") }, [], nil)

      # set alias
      TEST(lambda { AddOnProduct.SetRepoUrlAlias(@url, "SLES", "SLES-11-SP2") }, [], nil)

      nil
    end
  end
end

Yast::AddOnProductTestClient.new.main
