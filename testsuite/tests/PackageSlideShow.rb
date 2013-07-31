# encoding: utf-8

# Testsuite for PackageSlideShow.ycp module
#
# $Id:$
module Yast
  class PackageSlideShowClient < Client
    def main
      Yast.include self, "testsuite.rb"
      @READ = { "target" => { "tmpdir" => "/tmp" } }
      TESTSUITE_INIT([@READ], nil)

      Yast.import "PackageSlideShow"

      # no cut off
      TEST(lambda { PackageSlideShow.ListSumCutOff([60, 70, 80, 0], 100) }, [], nil)

      # one cut off
      TEST(lambda { PackageSlideShow.ListSumCutOff([60, 70, 80, 150], 100) }, [], nil)

      # more cut offs
      TEST(lambda { PackageSlideShow.ListSumCutOff([160, 170, 180, 10], 100) }, [], nil)

      nil
    end
  end
end

Yast::PackageSlideShowClient.new.main
