# encoding: utf-8

# Module:	inst_mediacopy.ycp
#
# Authors:	Anas Nashif <nashif@suse.de>
#
# Purpose:	Copy Media to local disk
#
# $Id$
#
module Yast
  class InstMediacopyClient < Client
    def main
      Yast.import "Pkg"
      textdomain "packager"

      Yast.import "Label"
      Yast.import "Popup"
      Yast.import "Wizard"
      Yast.import "Packages"
      Yast.import "PackageCallbacks"
      Yast.import "PackageCallbacksInit"
      Yast.import "Installation"
      Yast.import "GetInstArgs"
      Yast.import "String"

      @source_list = []

      # full initialization is required for Pkg::SourceMediaData()
      Packages.Init(true)
      @num = Builtins.size(Packages.theSources)
      if Ops.less_or_equal(@num, 0)
        Builtins.y2error("No repository")
      else
        Builtins.foreach(Packages.theSources) do |i|
          new_product = Pkg.SourceProductData(i)
          @source_list = Builtins.add(
            @source_list,
            Item(
              Id(i),
              Ops.get_string(new_product, "productname", "?"),
              Ops.get_string(new_product, "productversion", "?")
            )
          )
        end
      end

      # dialog heading
      @heading_text = _("Copy Installation Media")
      # help text
      @help_text = _(
        "<p>The installation CDs will be copied into the system\n" +
          "to create a repository that can be used to install\n" +
          "other systems.</p>\n"
      )
      # label for showing repositories
      @label = _("Registered Repositories")

      @contents = VBox(
        HCenter(
          HSquash(
            VBox(
              HSpacing(40), # force minimum width
              Left(Label(@label)),
              Table(Id(:sources), Header(_("Name"), _("Version")), @source_list)
            )
          )
        ),
        VSpacing(2)
      )

      Wizard.SetContents(
        @heading_text,
        @contents,
        @help_text,
        GetInstArgs.enable_back,
        GetInstArgs.enable_next
      )

      @dest = ""
      if SCR.Read(path(".target.dir"), Ops.add(Installation.destdir, "/export")) == nil
        SCR.Execute(
          path(".target.mkdir"),
          Ops.add(Installation.destdir, "/export")
        )
      end
      @dest = Ops.add(Installation.destdir, "/export")

      PackageCallbacksInit.SetMediaCallbacks

      @s = Pkg.SourceGetCurrent(false)
      Builtins.y2milestone("%1", @s)

      Builtins.foreach(@s) do |source|
        md = Pkg.SourceMediaData(source)
        pd = Pkg.SourceProductData(source)
        distprod = Ops.get_string(pd, "label", "")
        l = Builtins.splitstring(distprod, " ")
        distprod = Builtins.mergestring(l, "-")
        updir = Convert.to_string(SCR.Read(path(".etc.install_inf.UpdateDir")))
        __export = ""
        if updir == nil
          __export = Ops.add(@dest, "/dist")
        else
          __export = Ops.add(@dest, updir)
        end
        changed_url = false
        i = 1
        while Ops.less_or_equal(i, Ops.get_integer(md, "media_count", 0))
          tgt = Builtins.sformat("%1/%2/CD%3", __export, distprod, i)
          Builtins.y2debug("tgt: %1", tgt)
          #Popup::Message(sformat(_("Before... %1"), i ));
          dir = Pkg.SourceProvideDirectory(source, i, ".", false, false)
          #Popup::Message(sformat(_("After... %1"), i ));
          if dir != nil
            # feedback popup 1/2
            Popup.ShowFeedback(
              _("Copying CD contents to a local directory..."),
              # feedback popup 2/2
              _("Please wait...")
            )
            SCR.Execute(path(".target.mkdir"), tgt)
            #string cmd = sformat("cd %1 && tar cf - . | (cd %2  && tar xBf -)", dir,  tgt);
            cmd = Builtins.sformat(
              "cp '%1/content' '%2'",
              String.Quote(Builtins.tostring(dir)),
              String.Quote(tgt)
            )
            SCR.Execute(path(".target.bash"), cmd)

            if !changed_url
              Pkg.SourceChangeUrl(source, Ops.add("dir://", tgt))
              changed_url = true
            end

            Popup.ClearFeedback
          end
          i = Ops.add(i, 1)
        end
      end

      :next
    end
  end
end

Yast::InstMediacopyClient.new.main
