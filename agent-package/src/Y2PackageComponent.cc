

#include "Y2PackageComponent.h"
#include <scr/SCRInterpreter.h>
#include "PackageAgent.h"


Y2PackageComponent::Y2PackageComponent()
    : interpreter(0),
      agent(0)
{
}


Y2PackageComponent::~Y2PackageComponent()
{
    if (interpreter) {
        delete interpreter;
        delete agent;
    }
}


bool
Y2PackageComponent::isServer() const
{
    return true;
}


string
Y2PackageComponent::name() const
{
    return "ag_you";
}


YCPValue
Y2PackageComponent::evaluate(const YCPValue& value)
{
    if (!interpreter)
    {
	getSCRAgent ();
    }
    bool flag = interpreter->enableSubclassed (true);
    YCPValue v = interpreter->evaluate(value);
    interpreter->enableSubclassed (flag);
    return v;
}

SCRAgent*
Y2PackageComponent::getSCRAgent ()
{
    if (!interpreter)
    {
	agent = new PackageAgent ();
	interpreter = new SCRInterpreter (agent);
    }
    return agent;
}
