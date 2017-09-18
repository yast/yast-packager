#!/usr/bin/env rspec

require_relative "../test_helper"
require "y2packager/release_notes_reader"
require "y2packager/product"

describe Y2Packager::ReleaseNotesReader do
  subject(:reader) { described_class.new }

  let(:product) { instance_double(Y2Packager::Product, name: "dummy") }
  let(:package) { Y2Packager::Package.new("release-notes-dummy", 2, "15.1") }
  let(:dependencies) do
    [
      { "deps" => [{ "provides" => "release-notes() = dummy" }] }
    ]
  end

  let(:release_notes_store) do
    instance_double(Y2Packager::ReleaseNotesStore, clear: nil, retrieve: nil, store: nil)
  end

  let(:provides) do
    [["release-notes-dummy", :CAND, :NONE]]
  end

  let(:packages) { [package] }

  before do
    allow(Yast::Pkg).to receive(:PkgQueryProvides).with("release-notes()")
      .and_return(provides)
    allow(Yast::Pkg).to receive(:ResolvableDependencies)
      .with("release-notes-dummy", :package, "").and_return(dependencies)
    allow(Y2Packager::Package).to receive(:find).with(package.name)
      .and_return(packages)
    allow(package).to receive(:download_to) do |path|
      ::FileUtils.cp(FIXTURES_PATH.join("release-notes-dummy.rpm"), path)
    end
    allow(package).to receive(:status).and_return(:available)
    allow(Y2Packager::ReleaseNotesStore).to receive(:current)
      .and_return(release_notes_store)
  end

  describe "#release_notes_for" do
    it "returns product release notes in English" do
      rn = reader.release_notes_for(product)
      expect(rn.content).to eq("Release Notes\n")
      expect(rn.lang).to eq("en_US")
      expect(rn.user_lang).to eq("en_US")
    end

    it "cleans up temporary files" do
      dir = Dir.mktmpdir
      allow(Dir).to receive(:mktmpdir).and_return(dir)
      reader.release_notes_for(product)
      expect(File).to_not be_directory(dir)
    end

    it "stores the result for later retrieval" do
      expect(release_notes_store).to receive(:store)
        .with(Y2Packager::ReleaseNotes)
      reader.release_notes_for(product)
    end

    context "when the release notes were already downloaded" do
      let(:relnotes) { instance_double(Y2Packager::ReleaseNotes) }

      before do
        allow(release_notes_store).to receive(:retrieve)
          .and_return(relnotes)
      end

      it "does not download them again" do
        expect(reader.release_notes_for(product)).to eq(relnotes)
      end

      it "does not try to store the result" do
        expect(release_notes_store).to_not receive(:store)
        expect(reader.release_notes_for(product)).to eq(relnotes)
      end
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
        it "returns the English version" do
          rn = reader.release_notes_for(product, user_lang: "de_DE", format: :html)
          expect(rn.content).to eq("<h1>Release Notes</h1>\n")
          expect(rn.format).to eq(:html)
        end
      end
    end

    context "when release notes are not available" do
      it "returns the English version" do
        rn = reader.release_notes_for(product, user_lang: "es")
        expect(rn.content).to eq("Release Notes\n")
        expect(rn.lang).to eq("en_US")
        expect(rn.user_lang).to eq("es")
      end
    end

    context "when no package containing release notes was found" do
      let(:provides) { [] }

      it "returns nil" do
        expect(reader.release_notes_for(product)).to be_nil
      end

      it "does not try to store the result" do
        expect(release_notes_store).to_not receive(:store)
        reader.release_notes_for(product)
      end
    end

    context "when there is more than one package" do
      let(:other_package) { Y2Packager::Package.new("release-notes-dummy", 2, "15.0") }
      let(:packages) { [other_package, package] }

      before do
        allow(other_package).to receive(:status).and_return(:selected)
      end

      it "selects the latest one" do
        rn = reader.release_notes_for(product)
        expect(rn.version).to eq("15.1")
      end
    end

    context "when release package is not available/selected" do
      before do
        allow(package).to receive(:status).and_return(:removed)
      end

      it "ignores the package" do
        expect(reader.release_notes_for(product)).to be_nil
      end
    end
  end
end
