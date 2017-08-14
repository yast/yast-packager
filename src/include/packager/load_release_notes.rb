# encoding: utf-8

# File:	installation/include/load_release_notes.ycp
# Module:	Installation
# Summary:	Load release notes from media
# Authors:	Arvin Schnell <arvin@suse.de>
#              Jiri Srain <jsrain@suse.cz>
#
# Load release notes from media
#
# $Id: release_notes_popup.ycp 34411 2006-11-15 13:45:11Z locilka $
module Yast
  module PackagerLoadReleaseNotesInclude
    def initialize_packager_load_release_notes(_include_target)
      Yast.import "Pkg"
      textdomain "packager"

      Yast.import "Language"
      Yast.import "Report"
      Yast.import "Stage"

      # release notes
      @media_text = ""
    end

    # FIXME: get rid of similar funciton in instlalation/clients/release_notes_popup.ycp

    # function to load release notes
    def load_release_notes(source_id)
      if source_id.nil? || Ops.less_than(source_id, 0)
        Builtins.y2error("Source_id: %1", source_id)
        return false
      end

      path_to_relnotes = "/docu"
      filename_templ = UI.TextMode ? "/RELEASE-NOTES.%1.txt" : "/RELEASE-NOTES.%1.rtf"

      path_templ = path_to_relnotes + filename_templ
      Builtins.y2debug("Path template: %1", path_templ)

      # try 'en_UK' for 'en_UK'
      tmp = Builtins.sformat(path_templ, Language.language)
      Builtins.y2debug("Trying to get %1", tmp)
      tmp = Pkg.SourceProvideDigestedFile(
        source_id, # optional
        1,
        tmp,
        true
      )

      # try 'es' for 'es_ES'
      if tmp.nil?
        tmp = Builtins.sformat(
          path_templ,
          Builtins.substring(Language.language, 0, 2)
        )
        Builtins.y2debug("Trying to get %1", tmp)
        tmp = Pkg.SourceProvideDigestedFile(
          source_id, # optional
          1,
          tmp,
          true
        )
      end

      # try 'en'
      if tmp.nil?
        tmp = Builtins.sformat(path_templ, "en")
        Builtins.y2debug("Trying to get %1", tmp)
        tmp = Pkg.SourceProvideDigestedFile(
          source_id, # optional
          1,
          tmp,
          true
        )
      end

      # no other fallback
      return false if tmp.nil?

      # read the release notes content
      @media_text = Convert.to_string(
        SCR.Read(path(".target.string"), [tmp, ""])
      )
      return true if @media_text != "" && !@media_text.nil?

      false
    end
  end
end
