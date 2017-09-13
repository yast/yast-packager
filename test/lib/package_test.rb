#!/usr/bin/env rspec

require_relative "../test_helper"
require "y2packager/package"
require "fileutils"

describe Y2Packager::Package do
  subject(:package) { Y2Packager::Package.new("release-notes-dummy", 1, :available) }

  describe "#download_to" do
    let(:success) { true }

    before do
      allow(Yast::Pkg).to receive(:ProvidePackage)
        .with(package.repo_id, package.name, FIXTURES_PATH.to_s).and_return(success)
    end

    it "downloads package" do
      expect(Yast::Pkg).to receive(:ProvidePackage)
        .with(package.repo_id, package.name, FIXTURES_PATH.to_s).and_return(true)
      package.download_to(FIXTURES_PATH.to_s)
    end

    it "returns true" do
      expect(package.download_to(FIXTURES_PATH.to_s)).to eq(true)
    end

    context "when package download fails" do
      let(:success) { false }

      it "returns false" do
        expect(package.download_to(FIXTURES_PATH.to_s)).to eq(false)
      end
    end
  end

  describe "#extract_to" do
    let(:downloaded) { true }

    before do
      allow(package).to receive(:download_to).and_return(downloaded)
    end

    context "when the package is successfully downloaded" do
      after do
        ::FileUtils.rm_rf(FIXTURES_PATH.join("usr"))
      end

      it "extracts the content to the given path" do
        package.extract_to(FIXTURES_PATH.to_s)
        expect(File).to be_directory(
          FIXTURES_PATH.join("usr", "share", "doc", "release-notes", "dummy")
        )
      end

      it "returns true" do
        expect(package.extract_to(FIXTURES_PATH.to_s)).to eq(true)
      end
    end

    context "when the package could not be downloaded" do
      let(:downloaded) { false }

      it "returns false" do
        expect(package.extract_to(FIXTURES_PATH.to_s)).to eq(false)
      end
    end
  end
end
