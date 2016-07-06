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
end
