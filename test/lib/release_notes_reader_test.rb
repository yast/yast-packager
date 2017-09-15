#!/usr/bin/env rspec

require_relative "../test_helper"
require "y2packager/release_notes_reader"
require "y2packager/product"

describe Y2Packager::ReleaseNotesReader do
  subject(:reader) { described_class.new(work_dir) }

  let(:work_dir) { FIXTURES_PATH.join("release-notes") }
  let(:product) { instance_double(Y2Packager::Product, name: "dummy") }
  let(:package) { Y2Packager::Package.new("release-notes-dummy", 2, "15.0") }
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
      ::FileUtils.cp(FIXTURES_PATH.join("release-notes-dummy.rpm"), path)
    end
    allow(package).to receive(:status).and_return(:available)
    Y2Packager::ReleaseNotesStore.current.clear
  end

  describe "#release_notes_for" do
    it "returns product release notes in english" do
      rn = reader.release_notes_for(product)
      expect(rn.content).to eq("Release Notes\n")
      expect(rn.lang).to eq("en_US")
      expect(rn.user_lang).to eq("en_US")
    end

    it "cleans up temporary files" do
      reader.release_notes_for(product)
      expect(File).to_not be_directory(work_dir)
    end

    context "when a full language code is given (xx_XX)" do
      it "returns product release notes for the given language" do
        rn = reader.release_notes_for(product, user_lang: "en_US")
        expect(rn.content).to eq("Release Notes\n")
        expect(rn.lang).to eq("en_US")
        expect(rn.user_lang).to eq("en_US")
      end

      context "and release notes are not available" do
        it "returns product release notes for the short language code (xx)" do
          rn = reader.release_notes_for(product, user_lang: "de_DE")
          expect(rn.content).to eq("Versionshinweise\n")
          expect(rn.lang).to eq("de")
          expect(rn.user_lang).to eq("de_DE")
        end
      end
    end

    context "when a format is given" do
      it "returns product release notes in the given format" do
        rn = reader.release_notes_for(product, format: :html)
        expect(rn.content).to eq("<h1>Release Notes</h1>\n")
        expect(rn.format).to eq(:html)
      end

      context "and release notes are not available in the given format" do
        it "returns the english version" do
          rn = reader.release_notes_for(product, user_lang: "de_DE", format: :html)
          expect(rn.content).to eq("<h1>Release Notes</h1>\n")
          expect(rn.format).to eq(:html)
        end
      end
    end

    context "when release notes are not available" do
      it "returns the english version" do
        rn = reader.release_notes_for(product, user_lang: "es")
        expect(rn.content).to eq("Release Notes\n")
        expect(rn.lang).to eq("en_US")
        expect(rn.user_lang).to eq("es")
      end
    end

    context "when package could not be retrieved" do
      before do
        allow(package).to receive(:extract_to).and_return(false)
      end

      it "returns nil" do
        expect(reader.release_notes_for(product)).to be_nil
      end
    end

    context "when no package containing release notes was found" do
      let(:provides) { [] }

      it "returns nil" do
        expect(reader.release_notes_for(product)).to be_nil
      end
    end
  end

  after do
    ::FileUtils.rm_rf(work_dir) if work_dir.exist?
  end
end
