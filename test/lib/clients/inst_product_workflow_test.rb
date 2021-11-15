# Copyright (c) [2021] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require_relative "../../test_helper"
require "y2packager/clients/inst_product_workflow"

describe Y2Packager::Clients::InstProductWorkflow do
  subject(:client) { described_class.new }

  describe "#main" do
    let(:going_back) { false }
    let(:self_update_repo?) { true }
    let(:selected_product) { instance_double(Y2Packager::Product) }

    before do
      allow(Yast::GetInstArgs).to receive(:going_back).and_return(going_back)
      allow(Y2Packager::SelfUpdateAddonRepo).to receive(:present?).and_return(self_update_repo?)
      allow(Y2Packager::Product).to receive(:selected_base).and_return(selected_product)
      allow(Yast::WorkflowManager).to receive(:merge_product_workflow)
      allow(Yast::ProductControl).to receive(:RunFrom)
      allow(Yast::ProductControl).to receive(:CurrentStep).and_return(1)
    end

    it "merges the workflow from the selected product" do
      expect(Yast::WorkflowManager).to receive(:merge_product_workflow)
        .with(selected_product)
      client.main
    end

    it "runs the workflow from the next step" do
      expect(Yast::ProductControl).to receive(:RunFrom).with(2, true)
      client.main
    end

    context "if a self-update repository is present" do
      let(:self_update_repo?) { true }

      it "adds the self-update repository" do
        expect(Y2Packager::SelfUpdateAddonRepo).to receive(:create_repo)
        client.main
      end
    end

    context "if no self-update repository is present" do
      let(:self_update_repo?) { false }

      it "does not try to add a self-update repository" do
        expect(Y2Packager::SelfUpdateAddonRepo).to_not receive(:create_repo)
        client.main
      end
    end

    context "when going back" do
      let(:going_back) { true }

      it "returns :back" do
        expect(client.main).to eq(:back)
      end
    end
  end
end
