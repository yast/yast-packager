#
# Makefile.am for y2a_package/src
#

AM_CXXFLAGS = -DY2LOG=\"agent-package\"

plugin_LTLIBRARIES = libpy2ag_package.la
lib_LTLIBRARIES = liby2ag_package.la

liby2ag_package_la_SOURCES = 			\
	PackageCalls.cc PackageUpdateCalls.cc	\
	PackageAgent.cc PackageAgent.h
libpy2ag_package_la_LIBADD = -lpkg
liby2ag_package_la_LDFLAGS =			\
	-L$(top_srcdir)/libpkg/src		\
	-version-info 2:0

libpy2ag_package_la_SOURCES =			\
	$(liby2ag_package_la_SOURCES)		\
	Y2CCPackage.cc 	Y2CCPackage.h		\
	Y2PackageComponent.cc Y2PackageComponent.h
liby2ag_package_la_LIBADD = -lpkg
libpy2ag_package_la_LDFLAGS =			\
	-L$(top_srcdir)/libpkg/src		\
	-version-info 2:0

INCLUDES =					\
	-I$(top_srcdir)/libpkg/src/include	\
	-I$(includedir)
