#
# Makefile.am for y2scr/ycp/packages/agents
#

# liby2 only distinguishes between server and clients,
# since agents do a "service", they go to "servers_non_y2"

agent_SCRIPTS = ag_instsource

scrconf_DATA = $(patsubst $(srcdir)/%,%,$(wildcard $(srcdir)/*.scr))

EXTRA_DIST = $(agent_SCRIPTS) $(scrconf_DATA)
