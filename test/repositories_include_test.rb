#! /usr/bin/env rspec

require_relative "./test_helper"

# just a wrapper class for the repositories_include.rb
class RepositoryIncludeTester
  extend Yast::I18n
  Yast.include self, "packager/repositories_include.rb"
end

describe "PackagerRepositoriesIncludeInclude" do
  describe ".autorefresh" do
    # local protocols
    [ "cd", "dvd", "dir", "hd", "iso", "file" ].each do |protocol|
      url = "#{protocol}://foo/bar"
      it "returns false for local '#{url}' URL" do
        expect(RepositoryIncludeTester.autorefresh(url)).to eq(false)
      end
    end

    # remote protocols
    # see https://github.com/openSUSE/libzypp/blob/master/zypp/Url.cc#L464
    [ "http", "https", "nfs", "nfs4", "smb", "cifs", "ftp", "sftp", "tftp" ].each do |protocol|
      url = "#{protocol}://foo/bar"
      it "returns true for remote '#{url}' URL" do
        expect(RepositoryIncludeTester.autorefresh(url)).to eq(true)
      end
    end
    
    it "handles uppercase URLs correctly" do
      expect(RepositoryIncludeTester.autorefresh("FTP://FOO/BAR")).to eq(true)
      expect(RepositoryIncludeTester.autorefresh("DVD://FOO/BAR")).to eq(false)
    end
  end
end
