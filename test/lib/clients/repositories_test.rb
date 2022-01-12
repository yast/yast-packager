#!/usr/bin/env rspec

require_relative "../../test_helper"
require "packager/clients/repositories"

Yast.import "Pkg"
Yast.import "Popup"

describe Yast::RepositoriesClient do
  subject(:client) { Yast::RepositoriesClient.new }

  describe "#plugin_service_check" do
    SERVICE_NAME = "some-service".freeze
    MESSAGE = "Is a plugin".freeze

    before do
      allow(Yast::Pkg).to receive(:ServiceGet).with(SERVICE_NAME).and_return(service)
    end

    context "when the given service does not exist" do
      let(:service) { nil }

      it "returns true" do
        expect(client.plugin_service_check(SERVICE_NAME, MESSAGE)).to eq(true)
      end
    end

    context "when the given service is not a plugin" do
      let(:service) { { "type" => "product" } }

      it "returns true" do
        expect(client.plugin_service_check(SERVICE_NAME, MESSAGE)).to eq(true)
      end
    end

    context "when the given service is a plugin" do
      let(:service) { { "type" => "plugin" } }

      it "shows an error message" do
        expect(Yast::Popup).to receive(:Message).with(MESSAGE)
        client.plugin_service_check(SERVICE_NAME, MESSAGE)
      end

      it "returns false" do
        expect(client.plugin_service_check(SERVICE_NAME, MESSAGE)).to eq(false)
      end
    end
  end

  describe "#url_occupied?" do
    it "returns false for cd repository" do
      expect(client.url_occupied?("cd://")).to eq false
    end

    it "returns false for dvd repository" do
      expect(client.url_occupied?("dvd://")).to eq false
    end

    it "returns false when url is not yet used" do
      expect(client.url_occupied?("http://pepa.suse.cz/repo1")).to eq false
    end

    context "url already used for repository" do
      let(:url) { "http://pepa.suse.cz/repo1" }

      before do
        client.instance_variable_set(:@sourceStatesOut, [{ "SrcId" => "1" }])
      end

      it "returns false if repository is multi product media" do
        allow(Yast::Pkg).to receive(:SourceGeneralData).with(1).and_return(
          "url" => url, "product_dir" => "/product1"
        )

        expect(client.url_occupied?(url)).to eq false
      end

      it "returns true otherwise" do
        allow(Yast::Pkg).to receive(:SourceGeneralData).with(1).and_return(
          "url" => url, "product_dir" => "/"
        )

        expect(client.url_occupied?(url)).to eq true
      end
    end
  end

  describe "#warn_service_repository" do
    context "when the repository is managed by a service" do
      let(:source_state) { { "name" => "repo", "service" => "some-service", "SrcId" => "1" } }

      it "shows a warning message only once" do
        expect(Yast::Popup).to receive(:Warning).with(/manual changes might be reset/).once
        client.warn_service_repository(source_state)
        client.warn_service_repository(source_state)
      end
    end

    context "when the repository is not managed by a service" do
      let(:source_state) { { "name" => "repo", "service" => "", "SrcId" => "1" } }

      it "shows no warning message" do
        expect(Yast::Popup).to_not receive(:Warning)
        client.warn_service_repository(source_state)
      end
    end
  end

  describe "#SortReposByPriority" do
    it "returns nil if param is nil" do
      expect(client.SortReposByPriority(nil)).to eq nil
    end

    it "sorts by priorities" do
      repos = [
        { "priority" => 10, "name" => "repo1" },
        { "priority" => 30, "name" => "repo2" },
        { "priority" => 20, "name" => "repo3" }
      ]

      expected_output = [
        { "priority" => 10, "name" => "repo1" },
        { "priority" => 20, "name" => "repo3" },
        { "priority" => 30, "name" => "repo2" }
      ]

      expect(client.SortReposByPriority(repos)).to eq expected_output
    end

    it "sorts by name when priority is same" do
      repos = [
        { "priority" => 10, "name" => "repo1" },
        { "priority" => 30, "name" => "repo2" },
        { "priority" => 20, "name" => "repo4" },
        { "priority" => 20, "name" => "repo3" },
        { "priority" => 20, "name" => "repo5" }
      ]

      expected_output = [
        { "priority" => 10, "name" => "repo1" },
        { "priority" => 20, "name" => "repo3" },
        { "priority" => 20, "name" => "repo4" },
        { "priority" => 20, "name" => "repo5" },
        { "priority" => 30, "name" => "repo2" }
      ]

      expect(client.SortReposByPriority(repos)).to eq expected_output
    end
  end
end
