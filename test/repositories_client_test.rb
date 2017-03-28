#!/usr/bin/env rspec

require_relative "test_helper"
require_relative "../src/clients/repositories"

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
end
