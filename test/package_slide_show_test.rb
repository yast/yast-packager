#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "PackageSlideShow"

describe Yast::PackageSlideShow do
  subject(:package_slide_show) { Yast::PackageSlideShow }

  describe ".ListSum" do
    it "returns the sum skipping '-1' values" do
      expect(package_slide_show.ListSum([1, 2, 3, -1, 4])).to eq(10)
    end
  end

  describe ".ListSumCutOff" do
    it "returns sum of values if no value is over max_cutoff" do
      expect(Yast::PackageSlideShow.ListSumCutOff([60, 70, 80, 0], 100)).to eq 210
    end

    it "returns -x * max_cutoff where x is number of value higher then max_cutoff if any apear" do
      expect(Yast::PackageSlideShow.ListSumCutOff([60, 70, 80, 150], 100)).to eq(-100)
      expect(Yast::PackageSlideShow.ListSumCutOff([160, 170, 80, 150], 100)).to eq(-300)
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
end
