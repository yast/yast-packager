#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "PackageSlideShow"

describe Yast::PackageSlideShow do
  subject(:package_slide_show) { Yast::PackageSlideShow }

  describe ".ListSum" do
    it "returns the sum skipping negative values" do
      expect(package_slide_show.ListSum([1, 2, 3, -1, -2, 4])).to eq(10)
    end

    it "flattens list" do
      expect(package_slide_show.ListSum([[1, 2], 3, -1, -2, [4]])).to eq(10)
    end
  end

  describe ".SlideDisplayDone" do
    context "when deleting package" do
      it "increases removed counter in summary" do
        package_slide_show.main # to reset counter
        expect { package_slide_show.SlideDisplayDone("test", 1, true) }.to(
          change { package_slide_show.GetPackageSummary["removed"] }.from(0).to(1)
        )
      end

      it "adds name to removed_list in summary in normal mode" do
        allow(Yast::Mode).to receive(:normal).and_return(true)
        package_slide_show.main # to reset counter
        expect { package_slide_show.SlideDisplayDone("test", 1, true) }.to(
          change { package_slide_show.GetPackageSummary["removed_list"] }
            .from([])
            .to(["test"])
        )
      end
    end

    context "when installing package" do
      # TODO: lot of internal variables changes in size and time estimation that is hard to test
      # TODO: updating is also hard to test as it is set at start of package install
      # TODO: updating non trivial amount of table
      it "increases installed counter in summary" do
        package_slide_show.main # to reset counter
        expect { package_slide_show.SlideDisplayDone("test", 1, false) }.to(
          change { package_slide_show.GetPackageSummary["installed"] }.from(0).to(1)
        )
      end

      it "adds name to installed_list in summary in normal mode" do
        allow(Yast::Mode).to receive(:normal).and_return(true)
        package_slide_show.main # to reset counter
        expect { package_slide_show.SlideDisplayDone("test", 1, false) }.to(
          change { package_slide_show.GetPackageSummary["installed_list"] }
            .from([])
            .to(["test"])
        )
      end

      it "adds its size to installed_bytes in summary" do
        package_slide_show.main # to reset counter
        expect { package_slide_show.SlideDisplayDone("test", 502, false) }.to(
          change { package_slide_show.GetPackageSummary["installed_bytes"] }.from(0).to(502)
        )
      end

      it "sets global progress label in slide show" do
        expect(Yast::SlideShow).to receive(:SetGlobalProgressLabel)

        package_slide_show.SlideDisplayDone("test", 502, false)
      end

      it "updates stage progress" do
        expect(Yast::SlideShow).to receive(:StageProgress)

        package_slide_show.SlideDisplayDone("test", 502, false)
      end
    end
  end
end
