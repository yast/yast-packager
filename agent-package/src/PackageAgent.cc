//
// PackageAgent.cc
//
//
// Maintainer: Stefan Schubert ( schubi@suse.de )
//

#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <regex.h>
#include <string>

#include <YCP.h>
#include <ycp/YCPParser.h>
#include <ycp/y2log.h>
#include "PackageAgent.h"

/*==========================================================================
 * Public member functions
 *=========================================================================*/

/*--------------------------------------------------------------------------*
 * Constructor of the package agent
 *--------------------------------------------------------------------------*/
PackageAgent::PackageAgent()
{
   rawPackageInfo = NULL;
   solver = NULL;
   selSolver = NULL;
   selSaveSolver = NULL;
   packageInfoPath = "";
   commonPkd = "common.pkd";
   language = "";
   duDir = "";
   rootPath = "";
   yastPath = "";
   update = false;
   partitionSizeMap.clear();
   packageInstallMap.clear();
   selInstallMap.clear();
   additionalPackages.clear();
   unsolvedRequirements.clear();
   instPackageMap.clear();
   conflictMap.clear();
   obsoleteMap.clear();
   installSources = false;
   saveInstallSources = false;
}


/*--------------------------------------------------------------------------*
 * Destructor of the package agent
 *--------------------------------------------------------------------------*/
PackageAgent::~PackageAgent()
{
   y2milestone ( "~Y2PkgInfoComponent()" );

    if (rawPackageInfo)
	delete rawPackageInfo;
    rawPackageInfo = NULL;

    if (solver)
	delete solver;
    solver = NULL;

    if (selSolver)
	delete selSolver;
    selSolver = NULL;

    if (selSaveSolver)
	delete selSaveSolver;
    selSaveSolver = NULL;
}


/*--------------------------------------------------------------------------*
 * Execute path of the package agent
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::Execute (const YCPPath& path,
				const YCPValue& value,
				const YCPValue& arg)
{
   string path_name = path->component_str (0);
   YCPValue ret = YCPVoid();

   if (  path_name == SETENVIRONMENT )
   {
      // setting user and password for the you-server

      if ( !value.isNull()
	   && value->isMap() )
      {
	  ret = setEnvironment( value->asMap() );
      }
   }
   else if (  path_name  == SETINSTALLSELECTION )
   {
       if ( !value.isNull()
	    && value->isList()
	    && !arg.isNull()
	    && arg->isBoolean() )
       {
	   ret = setInstallSelection ( value->asList(),
				       arg->asBoolean()->value() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == SETDELETESELECTION )
   {
       if ( !value.isNull()
	    && value->isList())
       {
	   ret = setDeleteSelection ( value->asList() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == SETUPDATESELECTION )
   {
       if ( !value.isNull()
	    && value->isList())
       {
	   ret = setUpdateSelection ( value->asList() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == SELECTINSTALL )
   {
       if ( !value.isNull()
	    && value->isString()
	    && !arg.isNull()
	    && arg->isBoolean() )
       {
	   ret = selectInstall ( value->asString(),
				 arg->asBoolean() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == SELECTSELINSTALL )
   {
       if ( !value.isNull()
	    && value->isString()
	    && !arg.isNull()
	    && arg->isBoolean() )
       {
	   ret = selectSelInstall ( value->asString(),
				    arg->asBoolean() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == SELECTINSTALLLIST )
   {
       if ( !value.isNull()
	    && value->isList()
	    && !arg.isNull()
	    && arg->isBoolean() )
       {
	   ret = selectInstallList ( value->asList(),
				     arg->asBoolean() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == DESELECTINSTALL )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = deselectInstall ( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == DESELECTSELINSTALL )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = deselectSelInstall( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == SELECTUPDATE )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = selectUpdate( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == SELECTUPDATELIST )
   {
       if ( !value.isNull()
	    && value->isList() )
       {
	   ret = selectUpdateList( value->asList() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == DESELECTUPDATE )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = deselectUpdate( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == SELECTDELETE )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = selectDelete( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == DESELECTDELETE )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = deselectDelete( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == DELETEADDITIONALDEPENDENCIES )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = deleteAdditionalDependencies( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == DELETEUNSOLVEDREQUIREMENTS )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = deleteUnsolvedRequirements( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == DELETECONFLICTDEPENDENCIES )
   {
       if ( !value.isNull()
	    && value->isString()
	    && !arg.isNull()
	    && arg->isString() )
       {
	   ret = deleteConflictDependencies( value->asString(),
					     arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == DELETESELCONFLICTDEPENDENCIES )
   {
       if ( !value.isNull()
	    && value->isString()
	    && !arg.isNull()
	    && arg->isString() )
       {
	   ret = deleteSelConflictDependencies( value->asString(),
						arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == DELETESELUNSOLVEDREQUIREMENTS )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = deleteSelUnsolvedRequirements( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == SAVESTATE )
   {
        ret = saveState( );
   }
   else if (  path_name  == RESTORESTATE )
   {
        ret =restoreState( );
   }
   else if (  path_name  == DELETEOLDSTATE )
   {
        ret = deleteOldState( );
   }
   else if (  path_name  == SETSOURCEINSTALLATION )
   {
       if ( !value.isNull()
	    && value->isBoolean() )
       {
	   ret = setSourceInstallation( value->asBoolean() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == CHECKBROKENUPDATE )
   {
       ret = checkBrokenUpdate( );
   }
   else if (  path_name  == SAVEUPDATESTATUS )
   {
       if ( !value.isNull()
	    && value->isMap() )
       {
	   ret = saveUpdateStatus( value->asMap() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter", YCPBoolean( false ));
       }
   }
   else if (  path_name  == BACKUPUPDATESTATUS )
   {
       ret = backupUpdateStatus( );
   }
   else if (  path_name  == CHECKPACKAGE )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = checkPackage( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == CLOSEUPDATE )
   {
       if ( !value.isNull()
	    && value->isBoolean() )
       {
	   ret = closeUpdate( value->asBoolean() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == SEARCHPACKAGE )
   {
       if ( !value.isNull()
	    && value->isMap() )
       {
	   ret = searchPackage( value->asMap() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == COMPARESUSEVERSIONS )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = compareSuSEVersions( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name == CLOSEMEDIUM )
   {
       ret = closeMedium( );
   }
   else
   {
      y2error ( "Path %s not found", path_name.c_str() );
      ret = YCPError ("Agentpath not found", YCPVoid());
   }

   return ret;
}


/*--------------------------------------------------------------------------*
 * Read path of the package agent
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::Read(const YCPPath& path, const YCPValue& arg)
{
   string path_name = path->component_str (0);
   YCPValue ret = YCPVoid();

   if (  path_name == GETPACKAGELIST )
   {
       ret = getPackageList();
   }
   else if (  path_name  == GETHIERARCHYINFORMATION )
   {
       if ( !arg.isNull()
	    && arg->isMap() )
       {
	   ret = getHierarchyInformation( arg->asMap() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETSHORTNAME )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getShortName( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETLONGDESC )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getLongDesc( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETSHORTDESC )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getShortDesc( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETVERSION )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getVersion( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETDELDESC )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getDelDesc( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETSELDELDESC )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getSelDelDesc( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETCATEGORY )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getCategory( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETCOPYRIGHT )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getCopyright( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETAUTHOR )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getAuthor( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETSIZEINK )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getSizeInK( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETNOTIFYDESC )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getNotifyDesc( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETSELNOTIFYDESC )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getSelNotifyDesc( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETDEPENDENCIES )
   {
       ret = getDependencies( );
   }
   else if (  path_name  == GETSELDEPENDENCIES )
   {
       ret = getSelDependencies( );
   }
   else if (  path_name  == GETBREAKINGPACKAGELIST )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getBreakingPackageList( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETUPDATELIST )
   {
       ret = getUpdateList( );
   }
   else if (  path_name  == READVERSIONS )
   {
       ret = readVersions( );
   }
   else if (  path_name  == GETDISKSPACE )
   {
       if ( !arg.isNull()
	    && arg->isList() )
       {
	   ret = getDiskSpace( arg->asList() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETNEEDECDS )
   {
       ret = getNeededCDs( );
   }
   else if (  path_name  == GETINSTALLSET )
   {
       ret = getInstallSet( 0 ); // All packages
   }
   else if (  path_name  == GETINSTALLSETCD )
   {
       if ( !arg.isNull()
	    && arg->isInteger() )
       {
	   ret = getInstallSet( arg->asInteger()->value() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == PACKAGESELECTIONS )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = loadPackageSelections( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETSELINSTALLSET )
   {
       ret = getSelInstallSet( );
   }
   else if (  path_name  == GETUPDATESET )
   {
       ret = getUpdateSet( 0 ); // All packages
   }
   else if (  path_name  == GETUPDATESETCD )
   {
       if ( !arg.isNull()
	    && arg->isInteger() )
       {
	   ret = getUpdateSet( arg->asInteger()->value() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETUPDATEPACKAGENAMES )
   {
       ret = getUpdatePackageList();
   }
   else if (  path_name  == GETDELETESET )
   {
       ret = getDeleteSet( );
   }
   else if (  path_name  == ISSINGLESELECTED )
   {
       ret = isSingleSelected( );
   }
   else if (  path_name  == ISINSTALLSELECTED )
   {
       ret = isInstallSelected( );
   }
   else if (  path_name  == GETSELPACKAGES )
   {
       ret = getSelPackages( );
   }
   else if (  path_name  == GETSELGROUPS )
   {
       ret = getSelGroups( );
   }
   else if (  path_name  == ISCDBOOTED )
   {
       ret = isCDBooted( );
   }
   else if (  path_name  == GETPACKAGEVERSION )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getPackageVersion( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else if (  path_name  == GETCHANGEDPACKAGENAME )
   {
       ret = getChangedPackageName( );
   }
   else if (  path_name  == GETINSTALLSPLITTEDPACKAGES )
   {
       ret = getInstallSplittedPackages( );
   }
   else if (  path_name  == GETKERNELLIST )
   {
       ret = getKernelList( );
   }
   else if (  path_name  == GETPACKAGESTATUS )
   {
       if ( !arg.isNull()
	    && arg->isString() )
       {
	   ret = getPackageStatus( arg->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else
   {
      y2error ( "Path %s not found", path_name.c_str() );
      ret = YCPError ("Agentpath not found", YCPVoid());
   }

   return ret;
}


/*--------------------------------------------------------------------------*
 * Write path of the package agent
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::Write(const YCPPath& path, const YCPValue& value,
			 const YCPValue& arg)
{
   string path_name = path->component_str (0);
   YCPValue ret = YCPVoid();

   if (  path_name  == PACKAGESELECTIONS )
   {
       if ( !value.isNull()
	    && value->isString() )
       {
	   ret = savePackageSelections( value->asString() );
       }
       else
       {
	   ret = YCPError ("Wrong parameter");
       }
   }
   else
   {
       y2error ( "Path %s not found", path_name.c_str() );
       ret = YCPError ("Agentpath not found", YCPVoid());
   }

   return ret;
}


/*--------------------------------------------------------------------------*
 * Dir path of the you agent ( dummy )
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::Dir(const YCPPath& path)
{
   return YCPVoid ();
}

