#
# Makefile.am for y2a_package/src
#

AM_CXXFLAGS = -DY2LOG=\"agent-package\"

plugin_LTLIBRARIES = libpy2ag_package.la
lib_LTLIBRARIES = liby2ag_package.la

liby2ag_package_la_SOURCES = 			\
	PackageCalls.cc PackageUpdateCalls.cc	\
	PackageAgent.cc PackageAgent.h
liby2ag_package_la_LDFLAGS = -version-info 2:0

libpy2ag_package_la_SOURCES =			\
	$(liby2ag_package_la_SOURCES)		\
	Y2CCPackage.cc 	Y2CCPackage.h		\
	Y2PackageComponent.cc Y2PackageComponent.h
libpy2ag_package_la_LDFLAGS = -version-info 2:0

libpy2ag_package_la_LIBADD =			\
	-lpkg
liby2ag_package_la_LIBADD = $(libpy2ag_package_la_LIBADD)

INCLUDES = -I$(includedir)
