// -*- c++ -*-

#ifndef Y2CCPackage_h
#define Y2CCPackage_h

#include "Y2.h"

class Y2CCPackage : public Y2ComponentCreator
{
 public:
    /**
     * Creates a new Y2CCPackage object.
     */
    Y2CCPackage();
    
    /**
     * Returns true: The Package agent is a server component.
     */
    bool isServerCreator() const;
    
    /**
     * Creates a new @ref Y2SCRComponent, if name is "ag_you".
     */
    Y2Component *create(const char *name) const;
};

#endif
