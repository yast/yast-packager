require_relative "test_helper"
require "y2packager/installation_data"

describe Y2Packager::InstallationData do
  describe "#register_callback" do
    it "adds the default product callback" do
      expect(::Installation::InstallationInfo.instance)
        .to receive(:callback?).with("packager").and_return(false)

      expect(::Installation::InstallationInfo.instance)
        .to receive(:add_callback).with("packager")

      subject.register_callback
    end

    it "does not add the callback if it is already defined" do
      expect(::Installation::InstallationInfo.instance)
        .to receive(:callback?).with("packager").and_return(true)

      expect(::Installation::InstallationInfo.instance)
        .to_not receive(:add_callback)

      subject.register_callback
    end
  end
end
