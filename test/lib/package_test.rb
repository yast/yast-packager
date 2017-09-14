#!/usr/bin/env rspec

require_relative "../test_helper"
require "y2packager/package"
require "fileutils"

describe Y2Packager::Package do
  subject(:package) { Y2Packager::Package.new("release-notes-dummy", 1, :available) }

  let(:downloader) { instance_double(Packages::PackageDownloader, download: nil) }

  describe "#download_to" do
    it "downloads the package" do
      expect(Packages::PackageDownloader).to receive(:new)
        .with(package.repo_id, package.name).and_return(downloader)
      expect(downloader).to receive(:download).with(FIXTURES_PATH.to_s)
      package.download_to(FIXTURES_PATH)
    end

    context "when package download fails" do
      before do
        allow(downloader).to receive(:download)
          .and_raise(Packages::PackageDownloader::FetchError)
      end

      it "raises the error" do
        expect { package.download_to(FIXTURES_PATH) }
          .to raise_error(Packages::PackageDownloader::FetchError)
      end
    end
  end

  describe "#extract_to" do
    let(:extractor) { instance_double(Packages::PackageExtractor, extract: nil) }
    let(:tempfile) do
      instance_double(Tempfile, close: nil, unlink: nil, path: "/tmp/some-package") 
    end

    before do
      allow(Packages::PackageExtractor).to receive(:new).and_return(extractor)
      allow(Tempfile).to receive(:new).and_return(tempfile)
      allow(package).to receive(:download_to)
    end

    it "extracts the content to the given path" do
      expect(Packages::PackageExtractor).to receive(:new).with(tempfile.path)
        .and_return(extractor)
      expect(extractor).to receive(:extract).with("/path")
      package.extract_to("/path")
    end

    context "when the package could not be extracted" do
      before do
        allow(extractor).to receive(:extract)
          .and_raise(Packages::PackageExtractor::ExtractionFailed)
      end

      it "raises the error" do
        expect { package.extract_to("/path") }
          .to raise_error(Packages::PackageExtractor::ExtractionFailed)
      end
    end
  end
end
