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

require_relative "./test_helper"

Yast.import "InstShowInfo"

describe Yast::InstShowInfo do
  before do
    described_class.main
  end

  describe "#show_info_txt" do
    let(:path) { File.join(DATA_PATH, "README.BETA") }

    it "shows the file content" do
      expect(Yast::UI).to receive(:OpenDialog)
      subject.show_info_txt(path)
    end

    context "when a file with the same content was already shown" do
      before do
        subject.show_info_txt(path)
      end

      it "does not show the content" do
        expect(Yast::UI).to_not receive(:OpenDialog)
        subject.show_info_txt(path)
      end
    end
  end
end
