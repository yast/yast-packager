

#include "Y2CCPackage.h"
#include "Y2PackageComponent.h"
#include <ycp/y2log.h>

Y2CCPackage::Y2CCPackage()
    : Y2ComponentCreator(Y2ComponentBroker::BUILTIN)
{
}


bool
Y2CCPackage::isServerCreator() const
{
    return true;
}


Y2Component *
Y2CCPackage::create(const char *name) const
{
    if (!strcmp(name, "ag_package")) return new Y2PackageComponent();
    else return 0;
}


Y2CCPackage g_y2ccag_package;
