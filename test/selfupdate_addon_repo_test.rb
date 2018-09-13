#!/usr/bin/env rspec

require_relative "test_helper"
require "y2packager/selfupdate_addon_repo"

describe Y2Packager::SelfupdateAddonRepo do
  let (:path) { "/var/tmp/testing/path" }

  describe ".present?" do
    it "returns true if the repository path is a directory and is not empty" do
      expect(File).to receive(:exist?).with(path).and_return(true)
      expect(Dir).to receive(:empty?).with(path).and_return(false)

      expect(Y2Packager::SelfupdateAddonRepo.present?(path)).to be true
    end

    it "returns false if the repository path is an empty directory" do
      expect(File).to receive(:exist?).with(path).and_return(true)
      expect(Dir).to receive(:empty?).with(path).and_return(true)

      expect(Y2Packager::SelfupdateAddonRepo.present?(path)).to be false
    end

    it "returns false if the repository path does not exist" do
      expect(File).to receive(:exist?).with(path).and_return(false)

      expect(Y2Packager::SelfupdateAddonRepo.present?(path)).to be false
    end
  end

  describe ".create_repo" do
    it "adds a repository from the specified directory" do
      expect(Yast::Pkg).to receive(:SourceCreateType)
        .with("dir://#{path}?alias=SelfUpdate0", "", "Plaindir")
      Y2Packager::SelfupdateAddonRepo.create_repo(path)
    end
  end

  describe ".copy_packages" do
    let (:repo) { 42 }

    context "no addon package is found in the repository" do
      before do
        expect(Y2Packager::SelfupdateAddonFilter).to receive(:packages).with(repo)
          .and_return([])
      end

      it "returns false" do
        expect(Y2Packager::SelfupdateAddonRepo.copy_packages(repo)).to be false
      end

      it "does not create the repository" do
        expect(FileUtils).to_not receive(:mkdir_p)
        Y2Packager::SelfupdateAddonRepo.copy_packages(repo)
      end
    end

    context "an addon package is found in the repository" do
      before do
        expect(Y2Packager::SelfupdateAddonFilter).to receive(:packages).with(repo)
          .and_return(["pkg"])
        allow(FileUtils).to receive(:mkdir_p)
        allow_any_instance_of(Packages::PackageDownloader).to receive(:download)
      end

      it "returns true" do
        expect(Y2Packager::SelfupdateAddonRepo.copy_packages(repo)).to be true
      end

      it "creates the repository" do
        expect(FileUtils).to receive(:mkdir_p)
        Y2Packager::SelfupdateAddonRepo.copy_packages(repo)
      end

      it "downloads the packages" do
        expect_any_instance_of(Packages::PackageDownloader).to receive(:download)
        Y2Packager::SelfupdateAddonRepo.copy_packages(repo)
      end
    end
  end
end
