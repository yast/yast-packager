#!/usr/bin/env rspec

require_relative "../test_helper"
require "y2packager/release_notes_url_reader"
require "y2packager/product"

describe Y2Packager::ReleaseNotesUrlReader do
  subject(:reader) { described_class.new(product) }

  let(:product) { instance_double(Y2Packager::Product, name: "dummy") }
  let(:relnotes_url) { "http://doc.opensuse.org/openSUSE/release-notes-openSUSE.rpm" }
  let(:language) { double("Yast::Language", language: "de_DE") }
  let(:release_notes_index) { [] }

  before do
    allow(Yast::Pkg).to receive(:ResolvableProperties)
      .with(product.name, :product, "").and_return(["relnotes_url" => relnotes_url])
    allow(reader).to receive(:release_notes_index).and_return(release_notes_index)
    allow(reader).to receive(:release_notes_index).and_return(release_notes_index)
    allow(Yast::SCR).to receive(:Read).with(Yast::Path.new(".target.tmpdir"))
      .and_return("/tmp")
    allow(Yast::SCR).to receive(:Read).with(Yast::Path.new(".target.string"), /relnotes/)
      .and_return("Release Notes\n")
    described_class.clear_blacklist

    stub_const("Yast::Language", language)
    stub_const("Yast::Proxy", double("proxy"))
  end

  describe "#release_notes" do
    before do
      allow(reader).to receive(:curl_proxy_args).and_return("")
    end

    it "returns release notes" do
      cmd = %r{curl.*'http://doc.opensuse.org/openSUSE/RELEASE-NOTES.de_DE.txt'}
      expect(Yast::SCR).to receive(:Execute).with(Yast::Path.new(".target.bash"), cmd)
        .and_return(0)
      expect(Yast::SCR).to receive(:Read).with(Yast::Path.new(".target.string"), /relnotes/)
        .and_return("Release Notes\n")
      rn = reader.release_notes(user_lang: "de_DE", format: :txt)

      expect(rn.product_name).to eq("dummy")
      expect(rn.content).to eq("Release Notes\n")
      expect(rn.user_lang).to eq("de_DE")
      expect(rn.format).to eq(:txt)
      expect(rn.version).to eq(:latest)
    end

    context "when release notes are not found for the given language" do
      let(:user_lang) { "de_DE" }

      before do
        allow(Yast::SCR).to receive(:Execute)
          .with(Yast::Path.new(".target.bash"), /RELEASE-NOTES.#{user_lang}.txt/)
          .and_return(1)
      end

      it "returns release notes for the generic language" do
        expect(Yast::SCR).to receive(:Execute)
          .with(Yast::Path.new(".target.bash"), /RELEASE-NOTES.de.txt/)
          .and_return(0)
        reader.release_notes(user_lang: "de_DE", format: :txt)
      end

      context "and are not found for the generic language" do
        before do
          allow(Yast::SCR).to receive(:Execute)
            .with(Yast::Path.new(".target.bash"), /RELEASE-NOTES.de.txt/)
            .and_return(1)
        end

        it "falls back to 'en'" do
          expect(Yast::SCR).to receive(:Execute)
            .with(Yast::Path.new(".target.bash"), /RELEASE-NOTES.en.txt/)
            .and_return(0)
          reader.release_notes(user_lang: "de_DE", format: :txt)
        end
      end

      context "and the default language is 'en_*'" do
        let(:user_lang) { "en_US" }

        # bsc#1015794
        it "tries only 1 time with 'en'" do
          expect(Yast::SCR).to receive(:Execute)
            .with(Yast::Path.new(".target.bash"), /RELEASE-NOTES.en.txt/)
            .once.and_return(0)
          reader.release_notes(user_lang: "en_US", format: :txt)
        end
      end
    end

    context "when release notes index exists" do
      context "and wanted release notes are registered in that file" do
        let(:release_notes_index) do
          [
            "RELEASE-NOTES.de_DE.txt",
            "RELEASE-NOTES.en_US.txt"
          ]
        end

        it "tries to download release notes" do
          expect(Yast::SCR).to receive(:Execute)
            .with(Yast::Path.new(".target.bash"), /RELEASE-NOTES.de_DE.txt/)
            .and_return(0)
          reader.release_notes(user_lang: "de_DE", format: :txt)
        end
      end

      context "and wanted release notes are not registered in that file" do
        let(:release_notes_index) do
          [
            "RELEASE-NOTES.en_US.txt"
          ]
        end

        it "does not try to download release notes" do
          expect(Yast::SCR).to_not receive(:Execute)
            .with(Yast::Path.new(".target.bash"), /RELEASE-NOTES.de_DE.txt/)
          reader.release_notes(user_lang: "de_DE", format: :txt)
        end
      end
    end
  end

  describe "#curl_proxy_args" do
    before do
      allow(Yast::Proxy).to receive(:Read)
    end

    it "returns an empty string when no proxy is needed" do
      expect(Yast::Proxy).to receive(:enabled).and_return(false)
      expect(reader.curl_proxy_args).to eq ""
    end

    context "when a proxy is needed " do
      before do
        allow(Yast::Proxy).to receive(:enabled).and_return(true)
        allow(Yast::Proxy).to receive(:http).twice
          .and_return("http://proxy.example.com")
        test = {
          "HTTP" => {
            "tested" => true,
            "exit"   => 0
          }
        }
        allow(Yast::Proxy).to receive(:RunTestProxy).and_return(test)
      end

      it "returns correct args for an unauthenticated proxy" do
        allow(Yast::Proxy).to receive(:user).and_return("")
        allow(Yast::Proxy).to receive(:pass).and_return("")

        expect(reader.curl_proxy_args)
          .to eq "--proxy http://proxy.example.com"
      end

      it "returns correct args for an authenticated proxy" do
        allow(Yast::Proxy).to receive(:user).and_return("baggins")
        allow(Yast::Proxy).to receive(:pass).and_return("thief")

        expect(reader.curl_proxy_args)
          .to eq "--proxy http://proxy.example.com --proxy-user 'baggins:thief'"
      end
    end
  end
end
