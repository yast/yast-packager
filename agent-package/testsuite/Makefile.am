#
# Makefile.am for y2a_package/testsuite
#

AM_CXXFLAGS = -DY2LOG=\"agent-package\"

PACKAGE = ag_package
AUTOMAKE_OPTIONS = dejagnu

INCLUDES =					\
	-I$(top_srcdir)/libpkg/src/include	\
	-I$(includedir)

noinst_PROGRAMS = runag_package

runag_package_SOURCES = runag_package.cc
runag_package_LDADD = -ly2 -lpkg -lycp -lscr
runag_package_LDFLAGS = -L$(libdir)		\
	-Xlinker --whole-archive		\
	$(plugindir)/libpy2stdio.la		\
	$(plugindir)/libpy2plugin.la		\
	$(plugindir)/libpy2scr.la		\
	$(srcdir)/../src/libpy2ag_package.la	\
	-Xlinker --no-whole-archive
