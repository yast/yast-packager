#!/usr/bin/env rspec

require_relative "../test_helper"
require "y2packager/release_notes_reader"
require "y2packager/product"

describe Y2Packager::ReleaseNotesReader do
  subject(:reader) { described_class.new(product) }

  let(:product) { instance_double(Y2Packager::Product, name: "dummy") }

  let(:release_notes_store) do
    instance_double(Y2Packager::ReleaseNotesStore, clear: nil, retrieve: nil, store: nil)
  end

  let(:release_notes) do
    Y2Packager::ReleaseNotes.new(
      product_name: product.name,
      content:      "Release Notes\n",
      user_lang:    "en_US",
      lang:         "en_US",
      format:       :txt,
      version:      "15.0"
    )
  end

  let(:rpm_reader) do
    instance_double(
      Y2Packager::ReleaseNotesRpmReader,
      latest_version: "15.0",
      release_notes:  release_notes
    )
  end

  let(:url_reader) do
    instance_double(
      Y2Packager::ReleaseNotesRpmReader,
      latest_version: :latest,
      release_notes:  release_notes
    )
  end

  before do
    allow(Y2Packager::ReleaseNotesStore).to receive(:current)
      .and_return(release_notes_store)
    allow(Y2Packager::ReleaseNotesRpmReader).to receive(:new)
      .with(product).and_return(rpm_reader)
    allow(Y2Packager::ReleaseNotesUrlReader).to receive(:new)
      .with(product).and_return(url_reader)
  end

  describe "#release_notes" do
    before do
      allow(reader).to receive(:registered?).and_return(true)
    end

    context "when system is registered" do
      it "retrieves release notes from RPM packages" do
        expect(Y2Packager::ReleaseNotesRpmReader).to receive(:new)
          .with(product).and_return(rpm_reader)
        expect(rpm_reader).to receive(:latest_version).and_return("15.0")
        rn = reader.release_notes(user_lang: "en_US", format: :txt)
        expect(rn).to eq(release_notes)
      end

      context "when release notes are not found" do
        it "tries to get release notes from the relnotes_url property" do
          expect(Y2Packager::ReleaseNotesUrlReader).to receive(:new)
            .with(product).and_return(url_reader)
          rn = reader.release_notes(user_lang: "en_US", format: :txt)
          expect(rn).to eq(release_notes)
        end
      end
    end

    context "when system is not registered" do
      it "retrieves release notes from external sources" do
        expect(Y2Packager::ReleaseNotesUrlReader).to receive(:new)
          .with(product).and_return(url_reader)
        rn = reader.release_notes(user_lang: "en_US", format: :txt)
        expect(rn).to eq(release_notes)
      end

      context "when release notes are not found" do
        it "tries to get release notes from RPM packages" do
          expect(Y2Packager::ReleaseNotesRpmReader).to receive(:new)
            .with(product).and_return(rpm_reader)
          expect(rpm_reader).to receive(:latest_version).and_return("15.0")
          rn = reader.release_notes(user_lang: "en_US", format: :txt)
          expect(rn).to eq(release_notes)
        end
      end
    end

    it "stores the result for later retrieval" do
      expect(release_notes_store).to receive(:store)
        .with(release_notes)
      reader.release_notes
    end

    context "when the release notes were already downloaded" do
      let(:relnotes) { instance_double(Y2Packager::ReleaseNotes) }

      before do
        allow(release_notes_store).to receive(:retrieve)
          .and_return(release_notes)
      end

      it "does not download them again" do
        expect(reader.release_notes).to eq(release_notes)
      end

      it "does not try to store the result" do
        expect(release_notes_store).to_not receive(:store)
        expect(reader.release_notes).to eq(release_notes)
      end
    end
  end
end
