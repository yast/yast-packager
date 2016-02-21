#! /usr/bin/env rspec

require_relative "./test_helper"

Yast.import "PackageInstallation"

describe Yast::PackageInstallation do
  subject { Yast::PackageInstallation }

  describe "#Commit" do
    let(:config) { {"medium_nr" => 0} }
    let(:result) { [1, [], [], [], []] }

    before do
      allow(Yast::PackageSlideShow).to receive(:SetCurrentCdNo)
      allow(Yast::Pkg).to receive(:Commit).with(config)
        .and_return(result)
      allow(Yast::PackagesUI).to receive(:show_update_messages)
    end

    context "when running in normal mode" do
      it "shows a summary" do
        expect(Yast::PackagesUI).to receive(:SetPackageSummary)
        subject.Commit(config)
      end

      it "returns the commit result" do
        allow(Yast::PackagesUI).to receive(:SetPackageSummary)
        expect(subject.Commit(config)).to eq(result)
      end
    end

    context "when update messages are received" do
      let(:result) { [1, [], [], [], [message]] }
      let(:message) do
        {
          "solvable"         => "dummy-package",
          "text"             => "Some dummy text.",
          "installationPath" => "/var/adm/update-message/dummy-package-1.0",
          "currentPath"      => "/var/adm/update-message/dummy-package-1.0",
        }
      end

      it "shows the update messages" do
        expect(Yast::PackagesUI).to receive(:show_update_messages).with(result)
        subject.Commit(config)
      end

      context "in installation mode" do
        before do
          allow(Yast::Mode).to receive(:installation).and_return(true)
        end

        it "does not show the update messages" do
          expect(Yast::PackagesUI).to_not receive(:show_update_messages).with(result)
          subject.Commit(config)
        end
      end

      context "in autoinstallation mode" do
        before do
          allow(Yast::Mode).to receive(:autoinst).and_return(true)
        end

        it "does not show the update messages" do
          expect(Yast::PackagesUI).to_not receive(:show_update_messages).with(result)
          subject.Commit(config)
        end
      end
    end

    context "when installation fails" do
      let(:result) { nil }

      it "logs the error and returns []" do
        expect(Yast::Pkg).to receive(:Commit).with(config)
          .and_return(result)
        allow(Yast::Pkg).to receive(:LastError).and_return("error")
        expect(Yast::Builtins).to receive(:y2error).with(/Commit failed/, "error")
        expect(subject.Commit(config)).to eq([])
      end
    end
  end
end
