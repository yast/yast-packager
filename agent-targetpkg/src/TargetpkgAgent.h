/*
 * TargetpkgAgent.h
 *
 * An agent for handling installed packages
 *
 * Authors: Stefan Schubert <schubi@suse.de>
 *
 * $Id$
 */

#ifndef TargetpkgAgent_h
#define TargetpkgAgent_h


#include <ycp/YCPValue.h>
#include <scr/SCRAgent.h>
#include <scr/SCRInterpreter.h>
#include "RpmDb.h"


/**
 * @short SCR Agent for handling installed packages.
 */
class TargetpkgAgent : public SCRAgent
{

public:

    TargetpkgAgent ();
    ~TargetpkgAgent ();

    /**
     * Read data
     */
    YCPValue Read (const YCPPath& path, const YCPValue& arg = YCPNull());

    /**
     * Write data
     */
    YCPValue Write (const YCPPath& path, const YCPValue& value,
		    const YCPValue& arg = YCPNull());

    /**
     * Execute a command
     */
    YCPValue Execute (const YCPPath& path, const YCPValue& value = YCPNull(),
		      const YCPValue& arg = YCPNull());

    /**
     * Get a list of all subtrees
     */
    YCPValue Dir (const YCPPath& path) { return YCPList (); }

private:
    RpmDb * rpmDb_pC;
    bool    badDb_b;
    string  targetroot;
    string  backupPath;
private:
    RpmDb * rpmDb();
    bool    setTargetroot( const string & newTargetroot_tr );
private:
    YCPValue getInstalledKernel( );
    YCPValue getRebuildDbStatus( const bool start );
    YCPValue getAllPackageInfo();
    YCPValue backupPackage( string packageName );
    YCPValue touchDirectories ( string packageName );
    YCPValue removePackageLinks( string packageName );
    YCPValue updateRpmDb( );
    bool startRebuildDb( );
};


#endif // TargetpkgAgent_h
