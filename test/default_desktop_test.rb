#! /usr/bin/env rspec

require_relative "./test_helper"

Yast.import "DefaultDesktop"

describe Yast::DefaultDesktop do
  subject { Yast::DefaultDesktop }

  SUPPORTED_DESKTOPS_MOCKUP = [
    {
      "cursor"   => "DMZ",
      "desktop"  => "gnome",
      "icon"     => "pattern-gnome",
      "label_id" => "desktop_gnome",
      "logon"    => "gdm",
      "name"     => "gnome",
      "order"    => 1,
      "packages" => "gdm branding-openSUSE",
      "patterns" => "gnome x11 base"
    },
    {
      "cursor"   => "DMZ",
      "desktop"  => "kde",
      "icon"     => "pattern-kde",
      "label_id" => "desktop_kde",
      "logon"    => "sddm",
      "name"     => "kde",
      "order"    => 1,
      "packages" => "sddm branding-openSUSE",
      "patterns" => "kde x11 base"
    },
    {
      "cursor"   => "DMZ",
      "desktop"  => "xfce",
      "icon"     => "pattern-xfce",
      "label_id" => "desktop_xfce",
      "logon"    => "lightdm",
      "name"     => "xfce",
      "order"    => 4,
      "packages" => "lightdm branding-openSUSE",
      "patterns" => "xfce x11 base"
    },
    {
      "cursor"   => "DMZ",
      "desktop"  => "lxde",
      "icon"     => "pattern-lxde",
      "label_id" => "desktop_lxde",
      "logon"    => "lxdm",
      "name"     => "lxde",
      "order"    => 5,
      "packages" => "lxde-common branding-openSUSE",
      "patterns" => "lxde x11 base"
    },
    {
      "cursor"   => "DMZ",
      "desktop"  => "twm",
      "icon"     => "pattern-x11",
      "label_id" => "desktop_min_x",
      "logon"    => "xdm",
      "name"     => "min_x",
      "order"    => 6,
      "packages" => "xorg-x11 branding-openSUSE",
      "patterns" => "x11 base"
    },
    {
      "cursor"   => "DMZ",
      "desktop"  => "twm",
      "icon"     => "yast-sshd",
      "label_id" => "desktop_textmode",
      "logon"    => "xdm",
      "name"     => "textmode",
      "order"    => 8,
      "packages" => "branding-openSUSE",
      "patterns" => "minimal_base minimal_base-conflicts"
    }
  ].freeze

  def mock_product_features
    allow(Yast::ProductFeatures).to receive(:GetFeature)
      .with("software", "default_desktop").and_return("kde")
    allow(Yast::ProductFeatures).to receive(:GetFeature)
      .with("software", "supported_desktops")
      .and_return(SUPPORTED_DESKTOPS_MOCKUP.dup)
  end

  before do
    mock_product_features

    subject.ForceReinit
  end

  describe ".GetAllDesktopsMap" do
    it "returns hash with all desktops defined in product" do
      expect(subject.GetAllDesktopsMap.keys).to match_array(
        ["gnome", "kde", "min_x", "xfce", "lxde", "textmode"]
      )
    end
  end

  describe ".Desktop" do
    it "returns default desktop name if not set" do
      expect(subject.Desktop).to eq "kde"
    end

    it "returns name specified with #SetDesktop" do
      subject.SetDesktop("gnome")
      expect(subject.Desktop).to eq "gnome"
    end
  end
end
