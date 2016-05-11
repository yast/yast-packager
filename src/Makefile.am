# Sources for packager

module_DATA = \
  modules/InstShowInfo.rb \
  modules/DefaultDesktop.rb \
  modules/PackageInstallation.rb \
  modules/PackageSlideShow.rb \
  modules/ProductLicense.rb \
  modules/SpaceCalculation.rb \
  modules/SourceManager.rb \
  modules/AddOnProduct.rb \
  modules/InstURL.rb \
  modules/OneClickInstallStandard.rb \
  modules/Packages.rb \
  modules/SourceDialogs.rb \
  modules/SourceManagerSLP.rb \
  modules/KeyManager.rb \
  modules/CheckMedia.rb \
  modules/SlideShowCallbacks.rb

client_DATA = \
  clients/repositories.rb \
  clients/inst_check_memsize.rb \
  clients/select_slp_source.rb \
  clients/software_simple_proposal.rb \
  clients/inst_packages.rb \
  clients/key_manager.rb \
  clients/wrapper_storage.rb \
  clients/inst_checkmedia.rb \
  clients/inst_kickoff.rb \
  clients/media_proposal.rb \
  clients/do_not_show_again_editor.rb \
  clients/inst_rpmcopy.rb \
  clients/inst_custom_packages.rb \
  clients/inst_productsources.rb \
  clients/software_proposal.rb \
  clients/pkg_finish.rb \
  clients/inst_sw_select.rb \
  clients/sw_single.rb \
  clients/add_inst_source_slptype.rb \
  clients/inst_desktop.rb \
  clients/inst_mediacopy.rb \
  clients/wrapper_slideshow_callbacks.rb \
  clients/checkmedia.rb

yncludedir = @yncludedir@/packager
ynclude_DATA = \
  include/packager/key_manager_dialogs.rb \
  include/packager/storage_include.rb \
  include/packager/inst_source_dialogs.rb \
  include/packager/load_release_notes.rb \
  include/packager/repositories_include.rb

ylibdir = @ylibdir@/packager
ylib_DATA = lib/packager/product_patterns.rb

ynclude1dir = @yncludedir@/checkmedia
ynclude1_DATA = \
  include/checkmedia/ui.rb

scrconf_DATA = \
  scrconf/etc_zypp_conf.scr \
  scrconf/zypp_repos.scr

agent_SCRIPTS =	\
  servers_non_y2/ag_zypp_repos

desktop_DATA = \
  desktop/sw_source.desktop \
  desktop/sw_single.desktop \
  desktop/checkmedia.desktop

ylibclientdir = "${yast2dir}/lib/packager/clients"
ylibclient_DATA = \
  lib/packager/clients/pkg_finish.rb

EXTRA_DIST = $(module_DATA) $(client_DATA) $(ynclude_DATA) $(ynclude1_DATA) $(scrconf_DATA) $(agent_SCRIPTS) $(desktop_DATA) $(ylibclient_DATA) $(ylib_DATA)

include $(top_srcdir)/Makefile.am.common
