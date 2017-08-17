#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "PackageSlideShow"

describe Yast::PackageSlideShow do
  subject(:package_slide_show) { Yast::PackageSlideShow }

  describe "#ListSum" do
    it "returns the sum skipping '-1' values" do
      expect(package_slide_show.ListSum([1, 2, 3, -1, 4])).to eq(10)
    end
  end

  describe "#ListSumCutOff" do
    it "returns sum of values if no value is over max_cutoff" do
      expect(Yast::PackageSlideShow.ListSumCutOff([60, 70, 80, 0], 100)).to eq 210
    end

    it "returns -x * max_cutoff where x is number of value higher then max_cutoff if any apear" do
      expect(Yast::PackageSlideShow.ListSumCutOff([60, 70, 80, 150], 100)).to eq(-100)
      expect(Yast::PackageSlideShow.ListSumCutOff([160, 170, 80, 150], 100)).to eq(-300)
    end
  end
end
