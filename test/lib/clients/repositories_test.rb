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
      let (:url) { "http://pepa.suse.cz/repo1" }

      before do
        client.instance_variable_set(:"@sourceStatesOut", [{ "SrcId" => "1" }])
      end

      it "returns false if repository is multi product media" do
        allow(Yast::Pkg).to receive(:SourceGeneralData).with(1).and_return(
          { "url" => url, "product_dir" => "/product1" }
        )

        expect(client.url_occupied?(url)).to eq false
      end

      it "returns true otherwise" do
        allow(Yast::Pkg).to receive(:SourceGeneralData).with(1).and_return(
          { "url" => url, "product_dir" => "/" }
        )

        expect(client.url_occupied?(url)).to eq true
      end
    end
  end
end
