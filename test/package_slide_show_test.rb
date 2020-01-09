#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "PackageSlideShow"

describe Yast::PackageSlideShow do
  subject(:package_slide_show) { Yast::PackageSlideShow }

  describe ".ListSum" do
    it "returns the sum skipping negative values" do
      expect(package_slide_show.ListSum([1, 2, 3, -1, -2, 4])).to eq(10)
    end
  end

  describe ".SwitchToSecondsIfNecessary" do
    context "remaining time is already shown" do
      before do
        Yast::PackageSlideShow.unit_is_seconds = true
      end

      it "returns false" do
        expect(Yast::PackageSlideShow.SwitchToSecondsIfNecessary).to eq false
      end
    end

    context "remaining time is not yet shown" do
      before do
        Yast::PackageSlideShow.unit_is_seconds = false
      end

      context "initial delay does not pass yet" do
        before do
          allow(Yast2::SystemTime).to receive(:uptime).and_return(5)
          allow(Yast::SlideShow).to receive(:start_time).and_return(3)
          allow(Yast::SlideShow).to receive(:initial_recalc_delay).and_return(3)
        end

        it "returns false" do
          expect(Yast::PackageSlideShow.SwitchToSecondsIfNecessary).to eq false
        end
      end

      context "initial delay already pass" do
        before do
          allow(Yast2::SystemTime).to receive(:uptime).and_return(10)
          allow(Yast::SlideShow).to receive(:start_time).and_return(3)
          allow(Yast::SlideShow).to receive(:initial_recalc_delay).and_return(3)
        end

        it "returns false" do
          expect(Yast::PackageSlideShow.SwitchToSecondsIfNecessary).to eq true
        end

        it "sets to display remaining time" do
          Yast::PackageSlideShow.SwitchToSecondsIfNecessary

          expect(Yast::PackageSlideShow.show_remaining_time?).to eq true
        end

        it "recalculates remaining time" do
          expect(Yast::PackageSlideShow).to receive(:RecalcRemainingTimes)

          Yast::PackageSlideShow.SwitchToSecondsIfNecessary
        end
      end
    end
  end

  describe ".SlideDisplayDone" do
    context "when deleting package" do
      it "increases removed counter in summary" do
        Yast::PackageSlideShow.main # to reset counter
        expect{Yast::PackageSlideShow.SlideDisplayDone("test", 1, true)}.to(
          change{Yast::PackageSlideShow.GetPackageSummary["removed"]}.from(0).to(1)
        )
      end

      it "adds name to removed_list in summary in normal mode" do
        allow(Yast::Mode).to receive(:normal).and_return(true)
        Yast::PackageSlideShow.main # to reset counter
        expect{Yast::PackageSlideShow.SlideDisplayDone("test", 1, true)}.to(
          change{Yast::PackageSlideShow.GetPackageSummary["removed_list"]}.
            from([]).
            to(["test"])
        )
      end
    end

    context "when installing package" do
      # TODO: lot of internal variables changes in size and time estimation that is hard to test
      # TODO: updating is also hard to test as it is set at start of package install
      # TODO: updating non trivial amount of table
      it "increases installed counter in summary" do
        Yast::PackageSlideShow.main # to reset counter
        expect{Yast::PackageSlideShow.SlideDisplayDone("test", 1, false)}.to(
          change{Yast::PackageSlideShow.GetPackageSummary["installed"]}.from(0).to(1)
        )
      end

      it "adds name to installed_list in summary in normal mode" do
        allow(Yast::Mode).to receive(:normal).and_return(true)
        Yast::PackageSlideShow.main # to reset counter
        expect{Yast::PackageSlideShow.SlideDisplayDone("test", 1, false)}.to(
          change{Yast::PackageSlideShow.GetPackageSummary["installed_list"]}.
            from([]).
            to(["test"])
        )
      end

      it "adds its size to installed_bytes in summary" do
        Yast::PackageSlideShow.main # to reset counter
        expect{Yast::PackageSlideShow.SlideDisplayDone("test", 502, false)}.to(
          change{Yast::PackageSlideShow.GetPackageSummary["installed_bytes"]}.from(0).to(502)
        )
      end

      it "sets global progress label in slide show" do
        expect(Yast::SlideShow).to receive(:SetGlobalProgressLabel)

        Yast::PackageSlideShow.SlideDisplayDone("test", 502, false)
      end

      it "updates stage progress" do
        expect(Yast::SlideShow).to receive(:StageProgress)

        Yast::PackageSlideShow.SlideDisplayDone("test", 502, false)
      end
    end
  end
end
