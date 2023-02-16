#! /usr/bin/env rspec

require_relative "./test_helper"

Yast.import "SourceDialogs"

def allow_global_checkbox_state(enabled)
  allow(Yast::UI).to receive(:WidgetExists).with(:add_addon).and_return(true)
  allow(Yast::UI).to receive(:QueryWidget).with(:add_addon, :Value).and_return(enabled)
end

describe Yast::SourceDialogs do
  subject { Yast::SourceDialogs }

  ZYPP_VALID_URLS = [
    "cd:///",
    "dvd:/subdir?devices=/dev/sr0,/dev/sr1",
    "ftp://user:pass@server/path/to/media/dir",
    "ftp://user:pass@server/%2fhome/user/path/to/media/dir",
    "http://user:pass@server/path",
    "https://user:pass@server/path?proxy=foo&proxyuser=me&proxypass=pw",
    "hd:/subdir?device=/dev/sda1&filesystem=reiserfs",
    "dir:/directory/name",
    "iso:/?iso=CD1.iso&url=nfs://server/path/to/media",
    "iso:/?iso=CD1.iso&url=hd:/?device=/dev/hda",
    "iso:/subdir?iso=DVD1.iso&url=nfs://nfs-server/directory&mnt=/nfs/attach/point&filesystem=udf",
    "nfs://nfs-server/exported/path",
    "nfs://nfs-server/exported/path?mountoptions=ro&type=nfs4",
    "nfs4://nfs-server/exported/path?mountoptions=ro",
    "smb://servername/share/path/on/the/share",
    "cifs://usern:passw@servername/share/path/on/the/share?mountoptions=ro,noguest",
    "cifs://usern:passw@servername/share/path/on/the/share?workgroup=mygroup",
    "cifs://servername/share/path/on/the/share?user=usern&pass=passw"
  ].freeze

  describe "#valid_scheme?" do
    it "returns true for all known zypp uris" do
      ZYPP_VALID_URLS.each do |uri|
        expect(subject.valid_scheme?(uri)).to(eq(true), "Valid URI '#{uri}' is not recognized")
      end
    end

    it "returns true for 'https://' URL" do
      expect(subject.valid_scheme?("https://")).to eq(true)
    end

    it "returns false for empty URL and reports error" do
      expect(Yast::Report).to receive(:Error)
      expect(subject.valid_scheme?("")).to eq(false)
    end

    it "returns false for 'foo://' URL and reports error" do
      expect(Yast::Report).to receive(:Error)
      expect(subject.valid_scheme?("foo://")).to eq(false)
    end

    it "returns false for 'foo' URL and reports error" do
      expect(Yast::Report).to receive(:Error)
      expect(subject.valid_scheme?("foo")).to eq(false)
    end
  end

  describe "#PreprocessISOURL" do
    it "keeps additional URL parameter (workgroup)" do
      url = "iso:///?iso=openSUSE-12.2-DVD-i586.iso&workgroup=WORKGROUP&url=" \
            "smb://USERNAME:PASSWORD@192.168.1.66/install/images"
      converted = "smb://USERNAME:PASSWORD@192.168.1.66/install/images/" \
                  "openSUSE-12.2-DVD-i586.iso?workgroup=WORKGROUP"

      expect(subject.PreprocessISOURL(url)).to eq(converted)
    end

    it "handles escaped URL parameter" do
      url = "iso:///?workgroup=WORKGROUP&iso=openSUSE-12.2-DVD-i586.iso&url=" \
            "smb%3A%2F%2FUSERNAME%3APASSWORD%40192.168.1.66%2Finstall%2Fimages"
      converted = "smb://USERNAME:PASSWORD@192.168.1.66/install/images/" \
                  "openSUSE-12.2-DVD-i586.iso?workgroup=WORKGROUP"

      expect(subject.PreprocessISOURL(url)).to eq(converted)
    end

    it "handles iso with part in url and part in path" do
      converted = "iso:/insta%20ll/Duomenys%20600%20GB/openSUSE-13.2-DVD-x86_64.iso"
      url = "iso:/Duomenys%20600%20GB?iso=/openSUSE-13.2-DVD-x86_64.iso" \
            "&url=dir%3A%2Finsta%2520ll%2F"

      expect(subject.PreprocessISOURL(url)).to eq(converted)
    end

    it "handles properly escaped spaces" do
      converted = "iso:/install/Duomenys%20600%20GB/openSUSE-13.2-DVD-x86_64.iso"
      url = "iso:///?iso=openSUSE-13.2-DVD-x86_64.iso&" \
            "url=dir%3A%2Finstall%2FDuomenys%2520600%2520GB"

      expect(subject.PreprocessISOURL(url)).to eq(converted)
    end

    # empty iso url is used when adding new iso repository
    it "handles empty iso uri" do
      converted = ""
      url = "iso://"

      expect(subject.PreprocessISOURL(url)).to eq(converted)
    end
  end

  describe "#PostprocessISOURL" do
    it "keeps additional URL parameter (workgroup)" do
      converted = "smb://USERNAME:PASSWORD@192.168.1.66/install/images/" \
                  "openSUSE-12.2-DVD-i586.iso?workgroup=WORKGROUP"
      url = "iso:///?workgroup=WORKGROUP&iso=openSUSE-12.2-DVD-i586.iso&url=" \
            "smb%3A%2F%2FUSERNAME%3APASSWORD%40192.168.1.66%2Finstall%2Fimages"

      expect(subject.PostprocessISOURL(converted)).to eq(url)
    end

    it "uses dir url scheme parameter for local ISO files" do
      converted = "iso:///install/openSUSE-13.2-DVD-x86_64.iso"
      url_old = "iso:///?iso=openSUSE-13.2-DVD-x86_64.iso&url=dir%3A%2Finstall"
      url_new = "iso:///?iso=openSUSE-13.2-DVD-x86_64.iso&url=dir%3A%2F%2F%2Finstall"

      # Since Ruby 3.2, URI("dir:///foo").to_s no longer returns "dir:/foo"
      # It's OK with Zypp, it understands both forms
      expect([url_old, url_new]).to include(subject.PostprocessISOURL(converted))
    end

    it "prevents double escaping if get already escaped string" do
      converted = "iso:///install/Duomenys%20600%20GB/openSUSE-13.2-DVD-x86_64.iso"
      url_old = "iso:///?iso=openSUSE-13.2-DVD-x86_64.iso" \
                "&url=dir%3A%2Finstall%2FDuomenys%2520600%2520GB"
      url_new = "iso:///?iso=openSUSE-13.2-DVD-x86_64.iso" \
                "&url=dir%3A%2F%2F%2Finstall%2FDuomenys%2520600%2520GB"

      expect([url_old, url_new]).to include(subject.PostprocessISOURL(converted))
    end
  end

  describe ".IsISOURL" do
    it "returns true for iso with spaces" do
      url = "iso:///?iso=openSUSE-13.2-DVD-x86_64.iso&" \
            "url=dir%3A%2Finstall%2FDuomenys%2520600%2520GB"

      expect(subject.IsISOURL(url)).to eq true
    end
  end

  describe ".URLScheme" do
    it "returns scheme of url" do
      expect(subject.URLScheme("ftp://test.com")).to eq "ftp"
    end

    it "return \"url\" if parameter is empty string" do
      expect(subject.URLScheme("")).to eq "url"
    end

    it "return \"url\" if parameter is invalid url string" do
      expect(subject.URLScheme("test")).to eq "url"
    end
  end

  describe ".SelectStore" do
    it "sets url to full url for DVD and CD selection" do
      allow(Yast::UI).to receive(:QueryWidget).with(Id(:type), :CurrentButton)
        .and_return(:dvd)

      described_class.SelectStore(:type, {})

      expect(described_class.instance_variable_get("@_url")).to eq "dvd:///"
    end

    context "the global add-on checkbox is disabled" do
      before do
        allow_global_checkbox_state(false)
      end

      it "ignores the selected RadioButton" do
        expect(Yast::UI).to_not receive(:QueryWidget).with(Id(:type), :CurrentButton)
        described_class.SelectStore(:type, {})
      end

      it "sets empty URL" do
        described_class.SelectStore(:type, {})
        expect(described_class.instance_variable_get("@_url")).to eq ""
      end
    end
  end

  describe "SelectHandle" do
    context "the global add-on checkbox is disabled" do
      before do
        allow_global_checkbox_state(false)
      end

      it "returns nil after pressing [Next] even if the CD RadioButton is selected" do
        expect(Yast::UI).to receive(:QueryWidget).with(Id(:type), :CurrentButton).and_return(:cd)
        expect(described_class.SelectHandle(nil, "ID" => :next)).to eq(nil)
      end
    end

    context "the global add-on checkbox is enabled" do
      before do
        allow_global_checkbox_state(true)
      end

      it "returns :finish after pressing [Next] if the CD RadioButton is selected" do
        expect(Yast::UI).to receive(:QueryWidget).with(Id(:type), :CurrentButton).and_return(:cd)
        expect(described_class.SelectHandle(nil, "ID" => :next)).to eq(:finish)
      end
    end
  end

  describe "SelectValidate" do
    context "the global add-on checkbox is disabled" do
      before do
        allow_global_checkbox_state(false)
      end

      it "returns true" do
        expect(described_class.SelectValidate(nil, nil)).to eq(true)
      end

      it "ignores the RadioButton state" do
        expect(Yast::UI).to_not receive(:QueryWidget).with(Id(:type), :CurrentButton)
        described_class.SelectValidate(nil, nil)
      end
    end

    context "the global add-on checkbox is enabled" do
      before do
        allow_global_checkbox_state(true)
      end

      it "returns :finish after pressing [Next] if the CD RadioButton is selected" do
        expect(Yast::UI).to receive(:QueryWidget).with(Id(:type), :CurrentButton).and_return(:cd)
        expect(described_class.SelectHandle(nil, "ID" => :next)).to eq(:finish)
      end
    end
  end
end
