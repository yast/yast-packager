#
# Makefile.am for y2c_spkg/src
#

modulesdir = $(YAST2DIR)/clients
menudir = $(YAST2DIR)/menuentries
includedir = $(YAST2DIR)/include

modules_SCRIPTS = sw_single.ycp

menu_SCRIPTS = menuentry_sw_single.y2cc	\
		menuentry_sw_source.y2cc

include_DATA = require.ycp

EXTRA_DIST = $(modules_SCRIPTS) $(menu_SCRIPTS) $(include_DATA)
