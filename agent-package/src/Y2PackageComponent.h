// -*- c++ -*-

#ifndef Y2PackageComponent_h
#define Y2PackageComponent_h

#include "Y2.h"

class SCRInterpreter;
class PackageAgent;

class Y2PackageComponent : public Y2Component
{
    SCRInterpreter *interpreter;
    PackageAgent *agent;
    
public:
    
    /**
     * Create a new Y2PackageComponent
     */
    Y2PackageComponent();
    
    /**
     * Cleans up
     */
    ~Y2PackageComponent();
    
    /**
     * Returns true: The scr is a server component
     */
    bool isServer() const;
    
    /**
     * Returns "ag_you": This is the name of the you component
     */
    string name() const;
    
    /**
     * Evalutas a command to the scr
     */
    YCPValue evaluate(const YCPValue& command);

    /**
     * Returns the SCRAgent of the Y2Component, which of course is a
     * PackageAgent.
     */
    SCRAgent* getSCRAgent ();    
};

#endif
