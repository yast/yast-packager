#
# Makefile.am for packager/dirinstall
#
controldir = $(yast2dir)/control

control_DATA = \
	dirinstall.xml 

client_DATA = \
	dirinstall.ycp			\
	dirinstall_options_proposal.ycp	\
	dirinstall_options.ycp		\
	inst_dirinstall_finish.ycp		\
	inst_dirinstall.ycp

desktop_DATA = dirinstall.desktop

EXTRA_DIST = $(client_DATA) $(desktop_DATA) $(control_DATA)

include $(top_srcdir)/Makefile.am.common
