/*
 * TargetpkgAgent.cc
 *
 * An agent for handling installed packages
 *
 * Authors: Stefan Schubert <schubi@suse.de>
 *
 * $Id$
 */

#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include <config.h>
#include <YCP.h>
#include <y2/pathsearch.h>
#include <ycp/YCPParser.h>
#include <ycp/y2log.h>

#include "TargetpkgAgent.h"

//========================================================================


/**
 * Constructor
 */
TargetpkgAgent::TargetpkgAgent ()
    : rpmDb_pC  ( 0 )
    , badDb_b   ( false )
    , targetroot( "/" )
    , backupPath( "")
{
}

/**
 * Destructor
 */
TargetpkgAgent::~TargetpkgAgent ()
{
  delete rpmDb_pC;
}

///////////////////////////////////////////////////////////////////
//
//
//	METHOD NAME : TargetpkgAgent::rpmDb
//	METHOD TYPE : RpmDb *
//
//	DESCRIPTION : Return pointer to current RpmDb. If RpmDb is not
//      yet initialized, do it on the fly. If initialisation fails, set
//      badDb and return NULL. Usage of setTargetroot() will unset badDb
//      and trigger a reinitialisazion.
//
RpmDb * TargetpkgAgent::rpmDb()
{
  if ( rpmDb_pC || badDb_b )
    return rpmDb_pC;

  // Initialize the rpmDb according to current targetroot
  y2milestone( "Initialize rpmDb: Targetroot = %s", targetroot.c_str() );

  DbStatus dbStatus = DB_OK;
  bool     ok       = true;

  rpmDb_pC = new RpmDb( targetroot );
  dbStatus = rpmDb_pC->initDatabase( false ); // not create new db

  if ( dbStatus == DB_OLD_VERSION ) {
    y2warning( "create temporary-db" );
    ok = rpmDb_pC->createTmpDatabase( true ); // copy old db
  } else if ( dbStatus != DB_OK ) {
    ok = false;
  }

  badDb_b = !ok;

  if ( badDb_b ) {
    y2error( "init rpm-database" );
    delete rpmDb_pC;
    rpmDb_pC = 0;
  }

  return rpmDb_pC;
}

///////////////////////////////////////////////////////////////////
//
//
//	METHOD NAME : TargetpkgAgent::setTargetroot
//	METHOD TYPE : bool
//
//	DESCRIPTION : Set new targetroot and force reinitialisation
//      of rpmDb.
//
bool TargetpkgAgent::setTargetroot( const string & newTargetroot_tr )
{
  targetroot = newTargetroot_tr;
  y2milestone( "New targetroot = %s", targetroot.c_str() );

  delete rpmDb_pC;
  rpmDb_pC   = 0;
  badDb_b    = false;
  return rpmDb(); // reinitializes the rpmDb
}

/**
 * Read function
 */
YCPValue
TargetpkgAgent::Read (const YCPPath& path, const YCPValue& arg)
{
    YCPValue ret = YCPNull();

    y2debug ("Read (%s)", path->toString().c_str());

    if ( !rpmDb() )
    {
	return YCPError ("RPM-DB not initialized");
    }

    if ( path->isRoot() )
    {
	return YCPError ("Read () called without sub-path");
    }

    string cmd = path->component_str (0); // just a shortcut

    if (cmd == "dbPath")
    {
	return YCPString ( rpmDb()->queryCurrentDBPath() );
    }
    else if (cmd == "installedKernel")
    {
	ret = getInstalledKernel();
    }
    else if (cmd == "backupPath")
    {
	ret = YCPString( backupPath );
    }
    else if (cmd == "rebuildDbProgress")
    {
	ret = getRebuildDbStatus( false );
    }
    else if (cmd == "installed")
    {
	if (arg.isNull () || !arg->isString ())
	{
	    ret = YCPError
		("Bad packagename for Read (.installed, string package)");
	}
	else
	{
	    string version = rpmDb()->queryPackageVersion(
						arg->asString()->value());
	    if ( version != "" )
	    {
		ret = YCPBoolean ( true );
	    }
	    else
	    {
		ret = YCPBoolean ( false );
	    }
	}
    }
    else if (cmd == "info")
    {
	if (path->length()<2)
	{
	    // getting all information
	    ret = getAllPackageInfo();
	}
	else
	{
	    cmd = path->component_str (1);
	    if (cmd == "version")
	    {
		if (arg.isNull () || !arg->isString ())
		{
		    ret = YCPError
			("Bad packagename arg for Read (.info.version, string package)");
		}
		else
		{
		    ret = YCPString ( rpmDb()->queryPackageVersion(
						 arg->asString()->value() ) );
		}
	    }
	    else if (cmd == "release")
	    {
		if (arg.isNull () || !arg->isString ())
		{
		    ret = YCPError
			("Bad packagename arg for Read (.info.release, string package)");
		}
		else
		{
		    ret = YCPString ( rpmDb()->queryPackageRelease(
						 arg->asString()->value() ) );
		}
	    }
	    else if (cmd == "buildTime")
	    {
		if (arg.isNull () || !arg->isString ())
		{
		    ret = YCPError
			("Bad packagename arg for Read (.info.buildTime, string package)");
		}
		else
		{
		    time_t buildTime ( rpmDb()->queryPackageBuildTime(
						 arg->asString()->value() ) );

		    if ( buildTime > 0 )
		    {
			ret = YCPString ( ctime ( &buildTime ) );
		    }
		    else
		    {
			ret = YCPString ( "not known" );
		    }
		}
	    }
	    else if (cmd == "installTime")
	    {
		if (arg.isNull () || !arg->isString ())
		{
		    ret = YCPError
			("Bad packagename arg for Read (.info.installTime, string package)");
		}
		else
		{
		    time_t installTime ( rpmDb()->queryPackageInstallTime(
						 arg->asString()->value() ) );

		    if ( installTime > 0 )
		    {
			ret = YCPString ( ctime ( &installTime ) );
		    }
		    else
		    {
			ret = YCPString ( "not known" );
		    }
		}
	    }
	    else if (cmd == "vendor")
	    {
		if (arg.isNull () || !arg->isString ())
		{
		    ret = YCPError
			("Bad packagename arg for Read (.info.vendor, string package)");
		}
		else
		{
		    ret = YCPString ( rpmDb()->queryPackage( "%{VENDOR}",
							     arg->asString()->value() )  );
		}
	    }
	    else if (cmd == "summary")
	    {
		if (arg.isNull () || !arg->isString ())
		{
		    ret = YCPError
			("Bad packagename arg for Read (.info.summary, string package)");
		}
		else
		{
		    ret = YCPString ( rpmDb()->queryPackage( "%{SUMMARY}",
							     arg->asString()->value() )  );
		}
	    }	    	    
	    else if ( cmd == "fileList" ) {
		if ( arg.isNull() || !arg->isString() ) {
		  ret = YCPError( "Bad packagename arg for Read (.info.fileList, string package)" );
		} else {
		  FileList fileList;
		  if ( rpmDb()->queryInstalledFiles( fileList, arg->asString()->value() ) ) {
		    YCPList retList;
		    for ( FileList::const_iterator i = fileList.begin(); i != fileList.end(); ++i ) {
		      retList->add( YCPString( *i ) );
		    }
		    ret = retList;
		  } else {
		    ret = YCPVoid();
		  }
		}
	    }
	    else
	    {
		ret= YCPError (string("Undefined subpath for Read (.")
			       + path->toString() + ")");
	    }
	}
    }
    else
    {
	ret= YCPError (string("Undefined subpath for Read (.")
			 + path->toString() + ")");
    }

    return ret;
}


/**
 * Write function
 */
YCPValue
TargetpkgAgent::Write (const YCPPath& path, const YCPValue& value,
		    const YCPValue& arg)
{
    YCPValue ret = YCPNull();
    y2debug ("Write (%s)", path->toString().c_str());

    if (path->isRoot())
    {
	return YCPError ("Write () called without sub-path");
    }

    const string cmd = path->component_str (0); // just a shortcut

    if (cmd == "backupPath")
    {
	if (value.isNull() || !value->isString())
	{
	    y2error ("Bad path argument in call to Write (.backupPath)");
	    ret = YCPBoolean( false );
	}
	else
	{
	    backupPath = value->asString()->value();
	    ret = YCPBoolean( true );
	}
    }
    else if (cmd == "dbTargetPath")
    {
	if (value.isNull() || !value->isString())
	{
	    y2error ("Bad path argument in call to Write (.dbPath)");
	    ret = YCPBoolean( false );
	}
	else
	{
	  ret = YCPBoolean( setTargetroot( value->asString()->value() ) );
	}
    }
    else
    {
	ret = YCPError (string("Undefined subpath for Write (.")
			+ path->toString() + ")");
    }
    return ret;
}


/**
 * Execute functions
 */
YCPValue
TargetpkgAgent::Execute (const YCPPath& path, const YCPValue& value,
		      const YCPValue& arg)
{
    y2debug ("Execute (%s)", path->toString().c_str());
    YCPValue ret = YCPNull();

    if (path->isRoot ())
    {
	return YCPError ("Execute () called without sub-path");
    }

    if ( !rpmDb() )
    {
	return YCPError ("RPM-DB not initialized");
    }

    const string cmd = path->component_str (0); // just a shortcut

    if (cmd == "backup" )
    {
	if (value.isNull () || !value->isString ())
	{
	    ret = YCPError
		("Bad packagename value for "
		 "Execute(.backup, string package)");
	}
	else
	{
	    ret = backupPackage( value->asString()->value() );
	}
    }
    else if (cmd == "touchDirectories" )
    {
	if (value.isNull () || !value->isString ())
	{
	    ret = YCPError
		("Bad packagename value for "
		 "Execute(.touchDirectories, string package)");
	}
	else
	{
	    ret = touchDirectories( value->asString()->value() );
	}
    }
    else if (cmd == "removePackageLinks" )
    {
	if (value.isNull () || !value->isString ())
	{
	    ret = YCPError
		("Bad packagename value for "
		 "Execute(.removePackageLinks, string package)");
	}
	else
	{
	    ret = removePackageLinks( value->asString()->value() );
	}
    }
    else if (cmd == "updateDb" )
    {
	ret = updateRpmDb();
    }
    else if (cmd == "rebuildDb" )
    {
	if ( startRebuildDb() )
	{
	    getRebuildDbStatus( true );
	    ret = YCPBoolean( true );
	}
	else
	{
	    ret = YCPBoolean( false );
	}
    }
    else if (cmd == "checkSourcePackage" )
    {
	if (value.isNull () || !value->isString ())
	{
	    ret = YCPError
		("Bad packagename value for "
		 "Execute(.checkSourcePackage, string package)");
	}
	else
	{
	    if (value.isNull () || !value->isString ())
	    {
		ret = YCPBoolean(
			 rpmDb()->checkSourcePackage( value->asString()->value() ));
	    }
	    else
	    {
		ret = YCPBoolean(
			 rpmDb()->checkSourcePackage( value->asString()->value(),
						    arg->asString()->value()));
	    }
	}
    }
    else
    {
	ret = YCPError (string("Undefined subpath for Execute (.")
			+ path->toString() + ")");
    }

    return ret;
}

