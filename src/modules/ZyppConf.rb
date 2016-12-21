# encoding: utf-8

# File:    modules/ZyppConf.rb
# Summary: Setting /etc/zypp/zypp.conf
#
# $Id$
#
require "yast"

module Yast
  class ZyppConfClass < Module
    include Yast::Logger

    ZYPP_CONF_PATH = "/etc/zypp/zypp.conf"

    def main
      textdomain "packager"
      Yast.import "Report"
    end

    # Set libzypp to install only needed packages (no recommended, no docs, no multiversioning)
    # @param [Boolean] minimalistic true if only needed packages have to be installed
    def set_minimalistic(minimalistic)
      log.info("Set zypp.conf to minimalistic package selections: #{minimalistic}")

      # remove old headlines
      command = "/usr/bin/sed -i \'s/# set by YAST/\/g\' #{ZYPP_CONF_PATH}"
      SCR.Execute(path(".target.bash"), command)

      settings = {".*onlyRequires.*" => minimalistic ? "solver.onlyRequires = true" : "solver.onlyRequires = false",
        ".*rpm.install.excludedocs.*" => minimalistic ? "rpm.install.excludedocs = yes" : "rpm.install.excludedocs = no",
        "^multiversion =.*" => minimalistic ? "multiversion =" : "multiversion = provides:multiversion(kernel)"}
      settings.each do |match, replace|
        command = "/usr/bin/sed -i \'s/#{match}/\\n# set by YAST\\n#{replace}/g\' #{ZYPP_CONF_PATH}"
        if SCR.Execute(path(".target.bash"), command) != 0
          log.error "Error: #{command}"
          Report.Error("Cannot patch #{replace} in zypp.conf")
        end
      end
    end

    publish :function => :set_minimalistic, :type => "void (boolean)"
  end

  ZyppConf = ZyppConfClass.new
  ZyppConf.main
end
