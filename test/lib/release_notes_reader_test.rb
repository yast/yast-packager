#!/usr/bin/env rspec

require_relative "../test_helper"
require "y2packager/release_notes_reader"
require "y2packager/product"

describe Y2Packager::ReleaseNotesReader do
  subject(:reader) { described_class.new(work_dir) }

  let(:work_dir) { FIXTURES_PATH.join("release-notes") }

  let(:product) do
    instance_double(Y2Packager::Product, name: "dummy")
  end

  let(:package) do
    Y2Packager::Package.new("release-notes-dummy", 2, :available)
  end

  let(:dependencies) do
    [
      { "deps" => [{ "provides" => "release-notes() = dummy" }] }
    ]
  end

  let(:provides) do
    [["release-notes-dummy", :CAND, :NONE]]
  end

  before do
    allow(Yast::Pkg).to receive(:PkgQueryProvides).with("release-notes()")
      .and_return(provides)
    allow(Yast::Pkg).to receive(:ResolvableDependencies)
      .with("release-notes-dummy", :package, "").and_return(dependencies)
    allow(Y2Packager::Package).to receive(:find).with(package.name).and_return([package])
    allow(package).to receive(:download_to) do |path|
      ::FileUtils.mkdir_p(path) unless work_dir.directory?
      ::FileUtils.cp(FIXTURES_PATH.join("release-notes-dummy.rpm"), path)
      true
    end
  end

  describe "#for" do
    let(:download) { true }

    it "returns product release notes in english" do
      expect(reader.for(product)).to eq("Release Notes\n")
    end

    it "cleans up temporary files" do
      reader.for(product)
      expect(File).to_not be_directory(work_dir)
    end

    context "when a full language code is given (xx_XX)" do
      it "returns product release notes for the given language" do
        expect(reader.for(product, lang: "en_US")).to eq("Release Notes\n")
      end

      context "and release notes are not available" do
        it "returns product release notes for the short language code (xx)" do
          expect(reader.for(product, lang: "de_DE")).to eq("Versionshinweise\n")
        end
      end
    end

    context "when a format is given" do
      it "returns product release notes in the given format" do
        expect(reader.for(product, format: :html))
          .to eq("<h1>Release Notes</h1>\n")
      end

      context "and release notes are not available in the given format" do
        it "returns the english version" do
          expect(reader.for(product, lang: "de_DE", format: :html))
            .to eq("<h1>Release Notes</h1>\n")
        end
      end
    end

    context "when release notes are not available" do
      it "returns the english version" do
        expect(reader.for(product, lang: "es")).to eq("Release Notes\n")
      end
    end

    context "when package could not be retrieved" do
      before do
        allow(package).to receive(:extract_to).and_return(false)
      end

      it "returns nil" do
        expect(reader.for(product)).to be_nil
      end
    end

    context "when no package containing release notes was found" do
      let(:provides) { [] }

      it "returns nil" do
        expect(reader.for(product)).to be_nil
      end
    end
  end

  after do
    ::FileUtils.rm_rf(work_dir) if work_dir.exist?
  end
end
