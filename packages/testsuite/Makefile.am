#
# Makefile.am for .../testsuite
#

AUTOMAKE_OPTIONS = dejagnu
EXTRA_DIST = tests/empty.err tests/empty.out tests/empty.ycp

testsuite_prepare=/usr/lib/YaST2/testsuite/Makefile.testsuite

all-local: $(testsuite_prepare)
	make -f $(testsuite_prepare) RPMNAME=$(RPMNAME) srcdir=$(srcdir)

clean-local: $(testsuite_prepare)
	make -f $(testsuite_prepare) RPMNAME=$(RPMNAME) srcdir=$(srcdir) clean

# EOF
