#!/usr/bin/env rspec

require_relative "test_helper"

Yast.import "SlideShowCallbacks"

describe Yast::SlideShowCallbacksClass do
  subject { Yast::SlideShowCallbacksClass.new }

  describe "#DisplayStartInstall" do
    let(:pkg_name) { "libyui-ncurses-pkg-devel" }
    let(:pkg_location) { "pkg_location" }
    let(:pkg_description) { "pkg_description" }
    let(:pkg_size) { 138510 }
    let(:deleting) { false }

    before do
      allow(Yast::PackageSlideShow).to receive(:SlideDisplayStart)
      allow(subject).to receive(:HandleInput)
      allow(Yast::Installation).to receive(:destdir).and_return("/")
      allow(File).to receive(:exist?).and_return(true)
      allow(Yast::SlideShow).to receive(:SetUserAbort)

      subject.instance_variable_set(:@ask_again, true)
      subject.instance_variable_set(:@pkg_inprogress, pkg_name)
    end

    RSpec.shared_examples "free space check" do
      it "does not display the space warning when free space is >8EiB" do
        # sizes > 8EiB are returned as negative numbers (data overflow)
        expect(Yast::Pkg).to receive(:TargetAvailable).and_return(-42)
        expect(subject).to_not receive(:YesNoAgainWarning)

        subject.DisplayStartInstall(pkg_name, pkg_location, pkg_description, pkg_size, deleting)
      end

      it "does not display the space warning when free space is enough" do
        # 1MiB free space
        expect(Yast::Pkg).to receive(:TargetAvailable).and_return(1 << 20)
        expect(subject).to_not receive(:YesNoAgainWarning)

        subject.DisplayStartInstall(pkg_name, pkg_location, pkg_description, pkg_size, deleting)
      end

      it "displays the space warning when free space is not enough" do
        # 64KiB free space
        expect(Yast::Pkg).to receive(:TargetAvailable).and_return(1 << 16)
        expect(subject).to receive(:YesNoAgainWarning)

        subject.DisplayStartInstall(pkg_name, pkg_location, pkg_description, pkg_size, deleting)
      end
    end

    context "package data usage is available" do
      before do
        expect(Yast::Pkg).to receive(:PkgDU).with(pkg_name).and_return(
          # required space 230KiB
          "/" => [6854656, 4483116, 4483346, 0]
        )
      end

      include_examples "free space check"
    end

    context "package data usage is not available" do
      before do
        expect(Yast::Pkg).to receive(:PkgDU).with(pkg_name).and_return(nil)
      end

      include_examples "free space check"
    end
  end

  describe "ScriptProgress" do
    let(:input) { nil }

    before do
      allow(Yast::UI).to receive(:PollInput).and_return(input)
    end

    context "user does not click anything" do
      let(:input) { nil }

      it "returns true" do
        expect(subject.ScriptProgress(0, nil)).to eq true
      end
    end

    context "user click on abort" do
      let(:input) { :abort }

      it "returns false" do
        expect(subject.ScriptProgress(0, nil)).to eq false
      end
    end
  end
end
