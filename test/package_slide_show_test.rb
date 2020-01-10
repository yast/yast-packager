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

  describe ".SwitchToSecondsIfNecessary" do
    before do
      # set internal variable if showing time or not
      package_slide_show.instance_variable_set(:@unit_is_seconds, show_time)
    end

    context "remaining time is already shown" do
      let(:show_time) { true }

      it "returns false" do
        expect(package_slide_show.SwitchToSecondsIfNecessary).to eq false
      end
    end

    context "remaining time is not yet shown" do
      let(:show_time) { false }

      context "initial delay does not pass yet" do
        before do
          allow(Yast2::SystemTime).to receive(:uptime).and_return(5)
          allow(Yast::SlideShow).to receive(:start_time).and_return(3)
          allow(Yast::SlideShow).to receive(:initial_recalc_delay).and_return(3)
        end

        it "returns false" do
          expect(package_slide_show.SwitchToSecondsIfNecessary).to eq false
        end
      end

      context "initial delay already pass" do
        before do
          allow(Yast2::SystemTime).to receive(:uptime).and_return(10)
          allow(Yast::SlideShow).to receive(:start_time).and_return(3)
          allow(Yast::SlideShow).to receive(:initial_recalc_delay).and_return(3)
        end

        it "returns false" do
          expect(package_slide_show.SwitchToSecondsIfNecessary).to eq true
        end

        it "sets to display remaining time" do
          package_slide_show.SwitchToSecondsIfNecessary

          expect(package_slide_show.show_remaining_time?).to eq true
        end

        it "recalculates remaining time" do
          expect(package_slide_show).to receive(:RecalcRemainingTimes)

          package_slide_show.SwitchToSecondsIfNecessary
        end
      end
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

  describe ".FormatTimeShowOverflow" do
    it "formats time" do
      time = 1 * 3600 + 14 * 60 + 30
      expect(package_slide_show.FormatTimeShowOverflow(time)).to eq "1:14:30"
    end

    it "shows >MAX_TIME if time exceed MAX_TIME" do
      time = 14 * 60 + 30 + Yast::PackageSlideShowClass::MAX_TIME
      expect(package_slide_show.FormatTimeShowOverflow(time)).to eq ">2:00:00"
    end
  end

  describe ".CdStatisticsTableItems" do
    it "returns array of table items" do
      package_slide_show.main # to reset counter
      expect(package_slide_show.CdStatisticsTableItems).to be_a(::Array)
    end
  end
end
