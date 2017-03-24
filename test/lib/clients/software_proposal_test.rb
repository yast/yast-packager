#!/usr/bin/env rspec

require_relative "../../test_helper"
require "packager/clients/software_proposal"

describe Yast::SoftwareProposalClient do
  it "can be constructed" do
    expect { subject }.to_not raise_error
  end
end
