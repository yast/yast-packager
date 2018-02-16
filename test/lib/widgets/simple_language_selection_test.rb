#!/usr/bin/env rspec
# ------------------------------------------------------------------------------
# Copyright (c) 2018 SUSE LLC, All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it under
# the terms of version 2 of the GNU General Public License as published by the
# Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# ------------------------------------------------------------------------------

require_relative "../../test_helper"
require "y2packager/widgets/simple_language_selection"
require "cwm/rspec"
require "y2packager/product"

describe Y2Packager::Widgets::SimpleLanguageSelection do
  include_examples "CWM::AbstractWidget"

  subject(:widget) { described_class.new(["de_DE", "en", "cs"], default) }

  let(:default) { "en" }
  let(:languages_map) do
    {
      "de_DE" => ["Deutsch", "Deutsch", ".UTF-8", "@euro", "German"],
      "en_US" => ["English (US)", "English (US)", ".UTF-8", "", "English (US)"],
      "es_ES" => ["Español", "Espanol", ".UTF-8", "@euro", "Spanish"],
      "cs_CZ" => ["Čeština", "Cestina", ".UTF-8", "", "Czech"]
    }
  end

  before do
    allow(Yast::Language).to receive(:GetLanguagesMap).with(false)
      .and_return(languages_map)
  end

  describe "#init" do
    it "sets the widget's value to the default one" do
      expect(widget).to receive(:value=).with(default)
      widget.init
    end

    context "when full language code does not exist" do
      let(:default) { "cs_CZ" }

      it "tries using the short language code" do
        expect(widget).to receive(:value=).with("cs")
        widget.init
      end

      context "and short language code does not exist" do
        let(:default) { "es" }

        it "tries to the default 'en_US'" do
          expect(widget).to receive(:value=).with("en_US")
          widget.init
        end
      end
    end
  end

  describe "#items" do
    it "contains only given languages" do
      expect(widget.items).to eq(
        [["cs", "Czech"], ["en", "English (US)"], ["de_DE", "German"]]
      )
    end
  end

  describe "#opt" do
    it "sets the :notify option" do
      expect(widget.opt).to eq([:notify])
    end

    context "when there is only one option" do
      let(:languages_map) do
        { "en_US" => ["English (US)", "English (US)", ".UTF-8", "", "English (US)"] }
      end

      it "sets the :disabled option" do
        expect(widget.opt).to include(:disabled)
      end
    end
  end
end
