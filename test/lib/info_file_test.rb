#!/usr/bin/env rspec
# Copyright (c) [2019] SUSE LLC
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
require "y2packager/info_file"

describe Y2Packager::InfoFile do
  subject(:info_file) { described_class.read(readme_path) }
  let(:readme_path) { File.join(DATA_PATH, "README.BETA") }

  describe ".read" do
    it "reads the file from the given path" do
      file = described_class.read(readme_path)
      expect(file.content).to include("Attention!")
    end

    context "when the file does not exists" do
      it "returns nil" do
        file = described_class.read("does-not-exist.txt")
        expect(file).to be_nil
      end
    end
  end

  describe "#id" do
    it "returns a digest based ID" do
      expect(info_file.id).to start_with("999de")
    end
  end
end
