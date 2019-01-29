#!/usr/bin/env rspec

require_relative "test_helper"
require "y2packager/known_repositories"

describe Y2Packager::KnownRepositories do
  Yast.import "Pkg"

  let(:repo_url) { "http://example.com/repo" }
  let(:repos) { [repo_url] }
  let(:source_id) { 42 }

  before do
    allow(Yast::WFM).to receive(:scr_root).and_return("/")
  end

  describe "#repositories" do
    it "returns empty list if the file does not exist" do
      expect(File).to receive(:exist?).with(Y2Packager::KnownRepositories::STATUS_FILE)
        .and_return(false)
      expect(subject.repositories).to eq([])
    end

    it "reads the repository list from file" do
      expect(File).to receive(:exist?).with(Y2Packager::KnownRepositories::STATUS_FILE)
        .and_return(true)
      expect(YAML).to receive(:load_file).with(Y2Packager::KnownRepositories::STATUS_FILE)
        .and_return(repos)

      expect(subject.repositories).to eq(repos)
    end
  end

  describe "#write" do
    it "writes the known repositories to the file" do
      allow(subject).to receive(:repositories).and_return(repos)

      file = double("file")
      expect(File).to receive(:open).with(Y2Packager::KnownRepositories::STATUS_FILE, "w", 0o600)
        .and_yield(file)
      expect(file).to receive(:write).with(repos.to_yaml)

      subject.write
    end
  end

  describe "#new_repositories" do
    it "return the unknown repositories" do
      allow(subject).to receive(:repositories).and_return(repos)

      allow(Yast::Pkg).to receive(:SourceGetCurrent).with(true).and_return([source_id])
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(source_id)
        .and_return("url" => "http://new.example.com")

      expect(subject.new_repositories).to eq(["http://new.example.com"])
    end
  end

  describe "#update" do
    it "add the current repositories to the known repositories" do
      allow(subject).to receive(:repositories).and_return(repos)

      allow(Yast::Pkg).to receive(:SourceGetCurrent).with(true).and_return([source_id])
      allow(Yast::Pkg).to receive(:SourceGeneralData).with(source_id)
        .and_return("url" => "http://new.example.com")

      subject.update
      expect(repos).to eq(["http://example.com/repo", "http://new.example.com"])
    end
  end

end
