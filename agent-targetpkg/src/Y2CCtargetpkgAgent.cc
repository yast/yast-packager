

/*
 *  Author: Stefan Schubert <schubi@suse.de>
 */


#include <scr/Y2AgentComponent.h>
#include <scr/Y2CCAgentComponent.h>
#include <scr/SCRInterpreter.h>

#include "TargetpkgAgent.h"


typedef Y2AgentComp <TargetpkgAgent> Y2TargetpkgAgentComp;

Y2CCAgentComp <Y2TargetpkgAgentComp> g_y2ccag_targetpkg ("ag_targetpkg");

