#
# Handling of /etc/mtab and /mnt/etc/mtab
#
require "yast"

module Yast
  class MtabClass < Module
    include Yast::Logger

    MTABNAME = "/etc/mtab"

    def main
      Yast.import "Installation"
    end

    #
    # Reading /etc/mtab from inst-sys, removing all /mnt headings
    # and writing this patched mtab into target system.
    #
    def clone_to_target
      log.info("Copying /etc/mtab to the target system...")
      mtab = WFM.Read(path(".local.string"), MTABNAME)
      # remove non-existing mount points
      mtab_lines = mtab.split("\n")
      mtab_lines.collect! do |mtab_line|
        # Filter out all non-existing entries/directories
        columns = mtab_line.split
        if File.directory?(columns[1])
          # remove heading /mnt from directory entry
          columns[1].sub!(/^#{Regexp.escape("/mnt")}/, '')
          columns.join(" ")
        else
          nil
        end
      end

      # join back the lines
      mtab = mtab_lines.compact.join("\n")
      log.info("Target /etc/mtab file: #{mtab}")
      SCR.Write(path(".target.string"),
        File.join(Installation.destdir, MTABNAME), mtab)
    end

    publish :function => :clone_to_target, :type => "boolean ()"
  end

  Mtab = MtabClass.new
  Mtab.main
end
