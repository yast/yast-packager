#
# Makefile.am for y2a_package/testsuite
#

PACKAGE = ag_package
AUTOMAKE_OPTIONS = dejagnu

INCLUDES = -I$(includedir)

noinst_PROGRAMS = runag_package

runag_package_SOURCES = runag_package.cc
runag_package_LDADD = -ly2 -lpkg -lycp -lscr -lcrypt -lutil
runag_package_LDFLAGS = -L$(libdir)		\
	-Xlinker --whole-archive		\
	$(plugindir)/libpy2stdio.la		\
	$(plugindir)/libpy2plugin.la		\
	$(plugindir)/libpy2scr.la		\
	../src/libpy2ag_package.la		\
	-Xlinker --no-whole-archive
