require "yast"

# Yast namespace
module Yast
  # Handling of /etc/mtab and /mnt/etc/mtab
  class MtabClass < Module
    include Yast::Logger

    MTABNAME = "/etc/mtab".freeze

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
      mtab_lines.map! do |mtab_line|
        # Filter out all non-existing entries/directories
        columns = mtab_line.split
        next unless File.directory?(columns[1])
        # remove heading /mnt from directory entry
        columns[1] = columns[1][4..-1] if columns[1].start_with?("/mnt")
        columns.join(" ")
      end

      # join back the lines
      mtab = mtab_lines.compact.join("\n")
      log.info("Target /etc/mtab file: #{mtab}")
      SCR.Write(path(".target.string"),
        File.join(Installation.destdir, MTABNAME), mtab)
    end

    publish function: :clone_to_target, type: "boolean ()"
  end

  Mtab = MtabClass.new
  Mtab.main
end
