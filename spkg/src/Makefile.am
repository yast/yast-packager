#
# Makefile.am for y2c_spkg/src
#

modulesdir = $(YAST2DIR)/clients
menudir = $(YAST2DIR)/menuentries
includedir = $(YAST2DIR)/include

modules_SCRIPTS = sw_single.ycp		\
		sw_samba.ycp

menu_SCRIPTS = menuentry_sw_single.ycp	\
		menuentry_sw_source.ycp	\
		menuentry_sw_samba.ycp

include_DATA = require.ycp

EXTRA_DIST = $(modules_SCRIPTS) $(menu_SCRIPTS) $(include_DATA)
