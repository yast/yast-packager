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

require_relative "../test_helper"
require "y2packager/product_spec_reader"

describe Y2Packager::ProductSpecReader do
  let(:reader) { described_class.new }

  let(:full_reader) do
    instance_double(Y2Packager::ProductSpecReaders::Full, products: full_products)
  end

  let(:control_reader) do
    instance_double(Y2Packager::ProductSpecReaders::Control, products: control_products)
  end

  let(:libzypp_reader) do
    instance_double(Y2Packager::ProductSpecReaders::Libzypp, products: libzypp_products)
  end

  let(:full_products) { [instance_double(Y2Packager::ProductSpec, name: "SLES")] }
  let(:control_products) { [instance_double(Y2Packager::ProductSpec, name: "SLED")] }
  let(:libzypp_products) { [instance_double(Y2Packager::ProductSpec, name: "SLE-HA")] }
  let(:linuxrc_fake) { { foo: "bar" } }
  let(:linuxrc_empty) { {} }
  let(:linuxrc_keys) { linuxrc_fake }

  describe "#products" do
    before do
      allow(Y2Packager::ProductSpecReaders::Full).to receive(:new).and_return(full_reader)
      allow(Y2Packager::ProductSpecReaders::Control).to receive(:new).and_return(control_reader)
      allow(Y2Packager::ProductSpecReaders::Libzypp).to receive(:new).and_return(libzypp_reader)
      allow(Y2Packager::InstallationMedium).to receive(:contain_repo?).and_return(false)
      allow(Y2Packager::InstallationMedium).to receive(:contain_multi_repos?).and_return(false)
      allow(Yast::Mode).to receive(:normal).and_return(false)
      allow(Yast::Linuxrc).to receive(:keys).and_return(linuxrc_keys)
    end

    context "when medium does not contain any repository" do
      it "returns products from the control file" do
        expect(reader.products).to eq(control_products)
      end
    end

    context "when medium contain multiple repositories" do
      before do
        allow(Y2Packager::InstallationMedium).to receive(:contain_repo?).and_return(true)
        allow(Y2Packager::InstallationMedium).to receive(:contain_multi_repos?).and_return(true)
      end

      it "returns products from all repositories" do
        expect(reader.products).to eq(full_products)
      end
    end

    context "when medium contain single repository" do
      before do
        allow(Y2Packager::InstallationMedium).to receive(:contain_repo?).and_return(true)
      end

      it "returns the libzypp products" do
        expect(reader.products).to eq(libzypp_products)
      end
    end

    context "in installed system" do
      before do
        allow(Yast::Mode).to receive(:normal).and_return(true)
      end

      it "returns the libzypp products" do
        expect(reader.products).to eq(libzypp_products)
      end
    end

    context "without /etc/install.inf" do
      let(:linuxrc_keys) { linuxrc_empty }
      before do
        allow(Yast::Mode).to receive(:normal).and_return(false)
      end

      it "returns the libzypp products" do
        expect(reader.products).to eq(libzypp_products)
      end
    end
  end
end
