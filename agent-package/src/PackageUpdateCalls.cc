/*************************************************************
 *
 *     YaST2      SuSE Labs                        -o)
 *     --------------------                        /\\
 *                                                _\_v
 *           www.suse.de / www.suse.com
 * ----------------------------------------------------------
 *
 * File:	  PackageUpdateCalls.cc
 *
 * Author: 	  Stefan Schubert <schubi@suse.de>
 *
 * Description:   Agent package. Part: Update
 *		  calkulate disk-spaces.
 *
 * $Header$
 *
 *************************************************************/


#include <locale.h>
#include <libintl.h>
#include <stdlib.h>
#include <config.h>
#include <dirent.h>
#include <sys/stat.h>
#include <unistd.h>
#include <time.h>
#include <sys/types.h>
#include <utime.h>

#include "PackageAgent.h"
#include <scr/SCRAgent.h>
#include <scr/SCRInterpreter.h>
#include <Y2.h>
#include <YCP.h>
#include <ycp/y2log.h>
#include <pkg/ConfigFile.h>

#define MINDISTVERSION "MIN_DIST_VERSION"
#define DISTIDENT "DIST_IDENT"

#define DISTRIBUTIONVERSION "Distribution_Version"
#define DISTRIBUTIONNAME "Distribution_Name"
#define BASESYSTEM "Basesystem"
#define DISTRIBUTIONRELEASE "Distribution_Release"
#define TODELETE "Todelete"
#define TOINSTALL "Toinstall"
#define RMODE "RMode"
#define NOTARX "Notarx"
#define NOBACKUP "Nobackup"
#define DEFAULTINSTSRCFTP "DefaultInstsrcFTP"
#define PROHIBITED "Prohibited"

#define UPDATEBASE "updateBase"
#define INSTALLEDVERSION "installedVersion"
#define UPDATEVERSION "updateVersion"
#define PACKAGES "packages"
#define INSTALLEDGREATER "installedGreater"
#define PATHLEN		256
#define IMAGES "images"
#define SUSE "SuSE"


/***************************************************************************
 * Public Member-Functions						   *
 ***************************************************************************/


/*--------------------------------------------------------------------------*
 * Returns the list of packages, which replace old packages.
 * This packages have to be installed.
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getChangedPackageName(void)
{
   YCPList ret;

   y2milestone(  "CALLING getChangedPackageName" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ret;
   }

   if ( !update )
   {
      y2error( "Server not in update-modus" );
      return ret;
   }

   PackList installedPackages;
   PackList::iterator posInstalledPackage;

   installedPackages.clear();
   InstPackageMap::iterator posPackage;
   for ( posPackage = instPackageMap.begin();
	 posPackage != instPackageMap.end();
	 ++posPackage )
   {
       installedPackages.insert (  posPackage->first );
   }

   PackTagLMap providesMap = rawPackageInfo->getRawProvidesDependency();
   PackTagLMap::iterator posProvides;
   PackVersList packageList = rawPackageInfo->getRawPackageList( false );

   for ( posProvides = providesMap.begin(); posProvides != providesMap.end();
	 ++posProvides )
   {
      // checking every package in the common.pkd for provides flag.
      // If the package has a provide flag which in an installed
      // package and no longer on the distri, then this package have to
      // be installed

      PackageKey packageKey = posProvides->first;
      TagList tagList = posProvides->second;

      TagList::iterator posProvide;
      bool found = false;
      for ( posProvide = tagList.begin(); posProvide != tagList.end();
	    ++posProvide )
      {
	 // each provides-entry
	 // Check, if this provide-entry is a installed package
	 // and on the new distri
	 posInstalledPackage = installedPackages.find ( *posProvide );
	 if ( *posProvide != packageKey.name() &&  // not the packagename
	      posInstalledPackage != installedPackages.end() &&
	      !found )
	 {
	    bool onDistri = false;
	    PackVersList::iterator pos;
	    for ( pos = packageList.begin(); pos != packageList.end(); ++pos )
	    {
	       PackageKey distriPackageKey = *pos;
	       if ( distriPackageKey.name() == *posInstalledPackage )
	       {
		  y2milestone( "Old package %s found", (*posInstalledPackage).c_str() );
		  y2milestone( "But it is still on distri.-> %s will not be installed",
			       (packageKey.name()).c_str() );
		  onDistri = true;
		  break;
	       }
	    }

	    if ( !onDistri )
	    {
	       // old package is installed and no longer on the distri
	       // It is the task of rpm to delete the old rpm, but new
	       // package have to be installed
	       ret->add ( YCPString ( packageKey.name() ));

	       y2milestone( "Old package %s found", (*posInstalledPackage).c_str() );
	       y2milestone( "Replaced by %s in the rpm call",
			    (packageKey.name()).c_str() );
	       found = true;
	    }
	 }
      }
   }

   return ret;
}



/*--------------------------------------------------------------------------*
 * Returns a list of kernels which can be installed.
 * Argument: none
 * Format: $[ <kernel-name1>:<description1>, <kernel-name2>:
 *           <description2> ]
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getKernelList ( )
{
   YCPMap map;
   PackList::iterator pos;
   PackList serieList;

   y2debug( "CALLING getKernelList" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return map;
   }


   serieList = rawPackageInfo->getRawPackageListOfSerie( IMAGES );

   y2debug( "getKernelList: PACKAGES:" );

   for ( pos = serieList.begin(); pos != serieList.end(); ++pos )
   {
      string shortDescription = "";
      string longDescription = "";
      string notify = "";
      string delDescription = "";
      string category = "";
      string status = "";
      int size = 0;

      rawPackageInfo->getRawPackageDescritption( (string) *pos,
						 shortDescription,
						 longDescription,
						 notify,
						 delDescription,
						 category,
						 size);

      map->add ( YCPString( *pos ), YCPString( shortDescription ) );
      y2debug( "      %s",
	       ((string)*pos).c_str());
   }

   return ( map );
}



/*--------------------------------------------------------------------------*
 * Returns the list of packages, which have to be installed, cause
 * packages have been splitted.
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getInstallSplittedPackages(void)
{
   YCPList ret;

   y2debug( "CALLING getInstallSplittedPackages " );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ret;
   }

   if ( !update )
   {
      y2error( "Server not in update-modus" );
      return ret;
   }

   PackTagLMap providesMap = rawPackageInfo->getRawProvidesDependency();
   PackTagLMap::iterator posProvides;

   for ( posProvides = providesMap.begin(); posProvides != providesMap.end();
	 ++posProvides )
   {
      // each package in the common.pkd
      TagList  tagList = posProvides->second;
      TagList::iterator posList;
      for ( posList = tagList.begin();
	    posList != tagList.end();
	    ++posList )
      {
	 // each provides of a package
	 // Check, if there is a format like <package>:<file>
	 string tag = *posList;
	 string::size_type filePos = tag.find_first_of ( ":" );
	 if ( filePos != string::npos )
	 {
	    // entry found
	    y2debug( "Alias %s found", tag.c_str() );

	    string splittPackage = tag.substr ( 0, filePos );
	    string filename = rootPath + tag.substr ( filePos+1 );
	    struct stat check;

	    if ( stat ( filename.c_str(), &check) == 0 )
	    {
	       // file found
	       YCPList li;
	       PackageKey packageKey;
	       packageKey = posProvides->first;
	       li->add ( YCPString ( splittPackage ));
	       li->add ( YCPString ( packageKey.name() ));
	       ret->add ( YCPList ( li ) );
	       y2debug( "File %s found", filename.c_str() );
	    }
	    else
	    {
	       y2debug( "File %s NOT found", filename.c_str() );
	    }
	 }
      }
   }
   return ret;
}


/*--------------------------------------------------------------------------*
 * Save the update-status into /var/lib/YaST/install.lst
 * Input :$["ToDelete":"xyz1","aasdf",....],
 *          "ToInstall":["kaakl","aas"],
 *          "RMode":"Recover" ]
 * Return: ok
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::saveUpdateStatus ( const YCPMap &packageMap )
{
   ConfigFile info ( packageInfoPath + "/info" );
   Entries entriesInfo;
   Entries entriesLst;
   Entries::iterator pos;
   YCPBoolean ret = true;
   YCPList toDelete;
   YCPList toInstall;
   YCPString rMode("");

   y2debug( "CALLING saveUpdateStatus" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      ret = false;
      return ret;
   }

   if ( !update )
   {
      y2error( "Server not in update-modus" );
      ret = false;
      return ret;
   }

   YCPValue dummyValue = YCPVoid();

   dummyValue = packageMap->value(YCPString(TODELETE));
   if ( !dummyValue.isNull() && dummyValue->isList() )
   {
       toDelete  = dummyValue->asList();
   }
   dummyValue = packageMap->value(YCPString(TOINSTALL));
   if ( !dummyValue.isNull() && dummyValue->isList() )
   {
       toInstall  = dummyValue->asList();
   }
   dummyValue = packageMap->value(YCPString(RMODE));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
       rMode = dummyValue->asString();
   }

   string rmode = rMode->value();

   entriesInfo.clear();
   entriesLst.clear();

   // Reading info-file and get entry DISTIDENT
   info.readFile ( entriesInfo, " =" );

   pos = entriesInfo.find ( DISTIDENT );
   string infoName;
   if ( pos != entriesInfo.end() )
   {
      Values values = (pos->second).values;
      Values::iterator posValues;
      if ( values.size() >= 0 )
      {
	 posValues = values.begin();
	 infoName = *posValues;
      }
      else
      {
	 y2error( "DIST_IDENT in info not found" );
	 infoName = "";
	 ret = false;
      }
   }
   else
   {
      y2error( "DIST_IDENT in info not found" );
      infoName = "";
      ret = false;
   }

   if ( ret->value() )
   {
      // Splitting DISTIDENT into Distribution-name, -version
      // and release
      string::size_type    firstSeperator, secondSeperator;

      firstSeperator = infoName.find_last_of ( '-' );
      secondSeperator = infoName.find_first_of ( '#' );
      if ( firstSeperator != string::npos &&
	   secondSeperator != string::npos )
      {
	 Values values;
	 Element element;

	 // Basesystem
	 values.clear();
	 values.push_back ( infoName );
	 element.values = values;
	 element.multiLine = false;
	 entriesLst.insert(pair<const string, const Element>
				 ( BASESYSTEM, element ) );


	 // Distribution_Name
	 values.clear();
	 values.push_back ( infoName.substr ( 0 , firstSeperator ) );
	 element.values = values;
	 element.multiLine = false;
	 entriesLst.insert(pair<const string, const Element>
				 ( DISTRIBUTIONNAME, element ) );

	 // Distribution_Version
	 values.clear();
	 values.push_back ( infoName.substr ( firstSeperator+1,
					   secondSeperator -
					   firstSeperator - 1 ) );
	 element.values = values;
	 element.multiLine = false;
	 entriesLst.insert(pair<const string, const Element>
				 ( DISTRIBUTIONVERSION, element ) );

	 // Distribution_Release
	 values.clear();
	 values.push_back ( infoName.substr ( secondSeperator+1 ));
	 element.values = values;
	 element.multiLine = false;
	 entriesLst.insert(pair<const string, const Element>
				 ( DISTRIBUTIONRELEASE, element ) );

	 // RMode
	 values.clear();
	 values.push_back ( rmode );
	 element.values = values;
	 element.multiLine = false;
	 entriesLst.insert(pair<const string, const Element>
			   ( RMODE, element ) );
      }
      else
      {
	 y2error( "DIST_IDENT %s could not be splitted into components",
		  infoName.c_str());
	 ret = false;
      }
   }

   if ( ret->value() )
   {
      // saving Todelete

      int counter;
      Values values;
      Element element;

      for ( counter = 0; counter < toDelete->size(); counter++ )
      {
	 if ( toDelete->value(counter)->isString() )
	 {
	    string packageName(
		toDelete->value(counter)->asString()->value() );
	    values.push_back ( packageName );
	 }
      }

      element.values = values;
      element.multiLine = true;
      entriesLst.insert(pair<const string, const Element>
			( TODELETE, element ) );


      // saving Toinsert

      values.clear();

      for ( counter = 0; counter < toInstall->size(); counter++ )
      {
	 if ( toInstall->value(counter)->isString() )
	 {
	    string packageName(
		toInstall->value(counter)->asString()->value() );
	    values.push_back ( packageName );
	 }
      }

      element.values = values;
      element.multiLine = true;
      entriesLst.insert(pair<const string, const Element>
		     ( TOINSTALL, element ) );


      // save into file
      ConfigFile installLst( yastPath + "/install.lst"  );
      if (  !installLst.writeFile ( entriesLst,
		    "/var/lib/YaST/install.lst -- (c) 1998 SuSE GmbH",
				    ':' ) )
      {
	 y2error( "Error while writing the file /var/lib/YaST/install.lst" );
	 ret = false;
      }
   }

   return ret;

}



/*--------------------------------------------------------------------------*
 * Close Update and save  /var/lib/YaST/update.inf if it was successfully
 * Input : Base-System was updated
 * Return: ok
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::closeUpdate ( const YCPBoolean
					   &basesystemUpdated )
{
   ConfigFile info ( packageInfoPath + "/info" );
   ConfigFile updateInf( yastPath + "/update.inf"  );

   Entries entriesInfo;
   Entries entriesUpdate;
   Entries::iterator pos;
   YCPBoolean ret = true;
   bool basesystem = basesystemUpdated->value();

   y2debug( "CALLING closeUpdate" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      ret = false;
      return ret;
   }

   if ( !update )
   {
      y2error( "Server not in update-modus" );
      ret = false;
      return ret;
   }

   if ( basesystem )
   {
      //
      // saving update.inf
      //

      entriesInfo.clear();
      entriesUpdate.clear();

      // Reading info-file and get entry DISTIDENT
      info.readFile ( entriesInfo, " =" );

      // Reading old udpate.inf

      Values values;
      Element element;

      // Creating tree
      values.clear();
      element.values = values;
      element.multiLine = true;
      entriesUpdate.insert(pair<const string, const Element>
				 ( NOTARX, element ) );
      entriesUpdate.insert(pair<const string, const Element>
				 ( NOBACKUP, element ) );
      entriesUpdate.insert(pair<const string, const Element>
				 ( DEFAULTINSTSRCFTP, element ) );
      entriesUpdate.insert(pair<const string, const Element>
				 ( PROHIBITED, element ) );

      updateInf.readFile ( entriesUpdate, ":" );

      pos = entriesInfo.find ( DISTIDENT );
      string infoName;
      if ( pos != entriesInfo.end() )
      {
	 Values values = (pos->second).values;
	 Values::iterator posValues;
	 if ( values.size() >= 0 )
	 {
	    posValues = values.begin();
	    infoName = *posValues;
	 }
	 else
	 {
	    y2error( "DIST_IDENT in info not found" );
	    infoName = "";
	    ret = false;
	 }
      }
      else
      {
	 y2error( "DIST_IDENT in info not found" );
	 infoName = "";
	 ret = false;
      }

      if ( ret->value() )
      {
	 // Splitting DISTIDENT into Distribution-name, -version
	 // and release
	 string::size_type    firstSeperator, secondSeperator;

	 firstSeperator = infoName.find_last_of ( '-' );
	 secondSeperator = infoName.find_first_of ( '#' );
	 if ( firstSeperator != string::npos &&
	      secondSeperator != string::npos )
	 {
	    Values values;
	    Element element;

	    // Basesystem
	    values.clear();
	    values.push_back ( infoName );
	    element.values = values;
	    element.multiLine = false;
	    entriesUpdate.erase( BASESYSTEM );
	    entriesUpdate.insert(pair<const string, const Element>
				 ( BASESYSTEM, element ) );

	    // Distribution_Name
	    values.clear();
	    values.push_back ( infoName.substr ( 0 , firstSeperator ) );
	    element.values = values;
	    element.multiLine = false;
	    entriesUpdate.erase( DISTRIBUTIONNAME );
	    entriesUpdate.insert(pair<const string, const Element>
				 ( DISTRIBUTIONNAME, element ) );

	    // Distribution_Version
	    values.clear();
	    values.push_back ( infoName.substr ( firstSeperator+1,
						 secondSeperator -
						 firstSeperator - 1 ) );
	    element.values = values;
	    element.multiLine = false;
	    entriesUpdate.erase ( DISTRIBUTIONVERSION );
	    entriesUpdate.insert(pair<const string, const Element>
				 ( DISTRIBUTIONVERSION, element ) );

	    // Distribution_Release
	    values.clear();
	    values.push_back ( infoName.substr ( secondSeperator+1 ));
	    element.values = values;
	    element.multiLine = false;
	    entriesUpdate.erase ( DISTRIBUTIONRELEASE );
	    entriesUpdate.insert(pair<const string, const Element>
				 ( DISTRIBUTIONRELEASE, element ) );

	 }
	 else
	 {
	    y2error( "DIST_IDENT %s could not be splitted into components",
		     infoName.c_str());
	    ret = false;
	 }
      }

      // save into file
      if (  !updateInf.writeFile ( entriesUpdate,
				   "/var/lib/YaST/update.inf -- (c) 1998 SuSE GmbH",
				   ':' ) )
      {
	  y2error( "Error while writing the file update.inf" );
	  ret = false;
      }
   } // if basesystem

   return ret;
}


/*--------------------------------------------------------------------------*
 * Save the update-status from /var/lib/YaST/install.lst
 * to /var/lib/YaST/install.lst.bak
 *--------------------------------------------------------------------------*/
YCPValue     PackageAgent::backupUpdateStatus ( void )
{
   YCPBoolean ret = true;
   struct stat check;

   y2debug( "CALLING backupUpdateStatus" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      ret = false;
      return ret;
   }

   if ( !update )
   {
      y2error( "Server not in update-modus" );
      ret = false;
      return ret;
   }

   string source = yastPath + "/install.lst";
   string dest = yastPath + "/install.lst.bak";

   if ( stat ( source.c_str(), &check) == 0 )
   {
      remove ( dest.c_str() );

      if ( rename ( source.c_str(), dest.c_str() ) == -1 )
      {
	 y2error( "rename ( %s , %s )",
		  source.c_str(), dest.c_str());
	 ret = false;
      }
      else
      {
	 y2debug( "rename ( %s , %s ) OK",
		  source.c_str(), dest.c_str());
      }
   }

   return ret;
}


/*--------------------------------------------------------------------------*
 * Check, if the package has been installed without errors.
 * Input : package-name
 * Return: list; format:[<rpm-version>,<common.pkd-version>]
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::checkPackage ( const YCPString &packageName )
{
   string package = packageName->value();
   YCPList ret;
   string rpmVersion, commonVersion;
   long  commonBuildtime;
   bool ok = true;

   y2debug( "CALLING checkPackage" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   if ( !update )
   {
      y2error( "Server not in update-modus" );
      return YCPVoid();
   }

   YCPPath path = ".targetpkg.info.version";
   YCPValue retScr = mainscragent->Read( path,
				YCPString ( package ));
   if ( retScr->isString() )	// success
   {
       rpmVersion = retScr->asString()->value();
   }
   else
   {
       rpmVersion = "";
   }

   bool basePackage;
   int installationPosition;
   int cdNr;
   string instPath;
   int rpmSize;

   ok = rawPackageInfo->getRawPackageInstallationInfo( package,
				       basePackage,
				       installationPosition,
				       cdNr,
				       instPath,
				       commonVersion,
				       commonBuildtime,
				       rpmSize );

   if ( commonVersion != rpmVersion )
   {
      ok = false;
      y2error( "checkPackage returns version errors for package %s ",
	       package.c_str());
      y2error( "installed: %s; commonPKD: %s",
	       rpmVersion.c_str(), commonVersion.c_str() );
   }

   if ( !ok )
   {
      ret->add ( YCPString ( rpmVersion ) );
      ret->add ( YCPString ( commonVersion ) );
   }

   return ( ret );
}

/*--------------------------------------------------------------------------*
 * Evaluate the buildtime and version of a package
 * Input : package-name
 * Return: list; format:[<rpm-version>,<common.pkd-version>,<rpm-buildtime>,
 *                       <common.pkd-buildtime>]
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getPackageVersion ( const YCPString &packageName )
{
   string package = packageName->value();
   YCPList ret;
   string rpmVersion = "not known";
   string commonVersion = "not known";
   long rpmBuildtime = 0;
   long commonBuildtime = 0;
   bool ok = true;

   y2debug( "CALLING getPackageVersion" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   if ( !update )
   {
      y2error( "Server not in update-modus" );
      return YCPVoid();
   }

   InstPackageMap::iterator pos;

   pos = instPackageMap.find ( package );
   if ( pos != instPackageMap.end() )
   {
      InstPackageElement package = pos->second;
      rpmVersion = package.version;
      rpmBuildtime = package.buildtime;
   }

   bool basePackage;
   int installationPosition;
   int cdNr;
   string instPath;
   int	rpmSize;

   ok = rawPackageInfo->getRawPackageInstallationInfo( package,
				       basePackage,
				       installationPosition,
				       cdNr,
				       instPath,
				       commonVersion,
				       commonBuildtime,
				       rpmSize );

   time_t rpmTime ( rpmBuildtime );
   time_t commonTime ( commonBuildtime );

   ret->add ( YCPString ( rpmVersion ) );
   if ( rpmTime > 0 )
   {
      ret->add ( YCPString ( ctime ( &rpmTime ) ) );
   }
   else
   {
      ret->add ( YCPString ( "not known" ) );
   }
   ret->add ( YCPString ( commonVersion ) );
   if ( commonTime > 0 )
   {
      ret->add ( YCPString ( ctime ( &commonTime ) ) );
   }
   else
   {
      ret->add ( YCPString ( "not known" ) );
   }


   return ( ret );
}



/*--------------------------------------------------------------------------*
 * Calculates the packages which have to be updated  and returns a map like:
 * $["updateBase": TRUE ,
 *  "installedVersion":"SuSE 6.3",
 *  "updateVersion":"SuSE 6.4",
 *  "packages":$["aaa_base":"u", "xfree":"i", "asdfla":"d", "xyz":"m"....] ]
 * Flag "m" means that the user has to decide
 *--------------------------------------------------------------------------*/

YCPValue PackageAgent::getUpdateList(void)
{
   YCPMap ret;
   ConfigFile updateInf ( yastPath + "/update.inf" );
   ConfigFile info ( packageInfoPath + "/info" );
   Entries entriesUpdateInf;
   Entries entriesInfo;
   bool updateBaseSystem = false;
   string updateInfVersion;
   string updateInfName;
   string infoMinVersion;
   string infoName;

   y2debug( "CALLING getUpdatelist" );
   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   if ( !update )
   {
      y2error( "Server not in update-modus" );
      return YCPVoid();
   }

   entriesUpdateInf.clear();
   updateInf.readFile ( entriesUpdateInf, " :" );
   entriesInfo.clear();
   info.readFile ( entriesInfo, " =" );

   Entries::iterator pos;

   // reading variables from /var/lib/YaST/update.inf

   pos = entriesUpdateInf.find ( DISTRIBUTIONVERSION );
   if ( pos != entriesUpdateInf.end() )
   {
      Values values = (pos->second).values;
      Values::iterator posValues;
      if ( values.size() >= 0 )
      {
	 posValues = values.begin();
	 updateInfVersion = *posValues;
      }
      else
      {
	 y2error( "Distribution_Version in update.inf not found" );
	 updateInfVersion = "";
      }
   }
   else
   {
      y2error( "Distribution_Version in update.inf not found" );
      updateInfVersion = "";
   }

   pos = entriesUpdateInf.find ( BASESYSTEM );
   if ( pos != entriesUpdateInf.end() )
   {
      Values values = (pos->second).values;
      Values::iterator posValues;
      if ( values.size() >= 0 )
      {
	 posValues = values.begin();
	 updateInfName = *posValues;
      }
      else
      {
	 y2error( "Basesystem in update.inf not found" );
	 updateInfName = "";
      }
   }
   else
   {
      y2error( "Basesystem in update.inf not found" );
      updateInfName = "";
   }

   // reading variables from /var/adm/mount/suse/setup/descr/info

   pos = entriesInfo.find ( MINDISTVERSION );
   if ( pos != entriesInfo.end() )
   {
      Values values = (pos->second).values;
      Values::iterator posValues;
      if ( values.size() >= 0 )
      {
	 posValues = values.begin();
	 infoMinVersion = *posValues;
      }
      else
      {
	 y2error( "MIN_DIST_VERSION in info not found" );
	 infoMinVersion = "";
      }
   }
   else
   {
      y2error( "MIN_DIST_VERSION in info not found" );
      infoMinVersion = "";
   }

   pos = entriesInfo.find ( DISTIDENT );
   if ( pos != entriesInfo.end() )
   {
      Values values = (pos->second).values;
      Values::iterator posValues;
      if ( values.size() >= 0 )
      {
	 posValues = values.begin();
	 infoName = *posValues;
      }
      else
      {
	 y2error( "DIST_IDENT in info not found" );
	 infoName = "";
      }
   }
   else
   {
      y2error( "DIST_IDENT in info not found" );
      infoName = "";
   }

   // base-system to install ?

   y2debug( "Evaluate, if base-system has to be updated:" );
   y2debug( "    Compare installed:%s ", updateInfVersion.c_str() );
   y2debug( "    with MinVersion:%s",infoMinVersion.c_str() );

    if ( updateInfVersion.length() > infoMinVersion.length() )
    {
#if defined __GNUC__ && __GNUC__ >= 3
	updateBaseSystem = infoMinVersion.compare (0, infoMinVersion.length (), updateInfVersion) > 0;
#else
	updateBaseSystem = infoMinVersion.compare (updateInfVersion, 0, infoMinVersion.length ()) > 0;
#endif
    }
    else
    {
#if defined __GNUC__ && __GNUC__ >= 3
	updateBaseSystem = updateInfVersion.compare (0, updateInfVersion.length (), infoMinVersion) < 0;
#else
	updateBaseSystem = updateInfVersion.compare (infoMinVersion, 0, updateInfVersion.length ()) < 0;
#endif
    }

   InstPackageMap::iterator posPackage;
   YCPMap packages;
   PackTagLMap obsoletesMap = rawPackageInfo->getRawObsoletesDependency();
   PackTagLMap::iterator posObsoletes;

   for ( posPackage = instPackageMap.begin();
	 posPackage != instPackageMap.end();
	 ++posPackage )
   {
      // evaluate all installed packages which have to be updated
      // or have to be deleted cause they are not supported SuSE packages
      string versionNew;
      long buildTimeNew = 0;
      bool basePackage = 0;
      string modus = "";
      CompareVersion compareVersion;

      InstPackageElement installedPackage = posPackage->second;
      string versionInstalled = installedPackage.version;
      long buildTimeInstalled = installedPackage.buildtime;

      string dummy1;
      int dummy2, dummy3;
      int rpmSize;

      rawPackageInfo->getRawPackageInstallationInfo(
						 installedPackage.packageName,
						 basePackage,
						 dummy2, dummy3, dummy1,
						 versionNew, // reference
						 buildTimeNew,
						 rpmSize );
      // This function returns always true. So we will have to check for size in order
      // to check, if the package is on the current pkd
      if ( versionNew.size() > 0 )
      {
	  // installed package is in the current common.pkd
	  if ( updateBaseSystem &&
	       basePackage )
	  {
	      // Basepackage will be updated, cause the release has
	      // been changed
	      modus = "u";
	  }
	  else
	  {
	      y2debug( "compare %s Version new %s <-> installed %s",
		       (posPackage->first).c_str(),
		       versionNew.c_str(),
		       versionInstalled.c_str() );

	      compareVersion = CompVersion ( versionNew.c_str(),
					versionInstalled.c_str() );
	      y2debug( "Buildtime new %ld <-> installed %ld",
		       buildTimeNew, buildTimeInstalled );

	      if (  ( compareVersion == V_OLDER &&
		      buildTimeNew <= buildTimeInstalled ) ||
		    ( compareVersion == V_EQUAL  &&
		      buildTimeNew == buildTimeInstalled )
		    )
	      {
		  // no installation
		  modus = "i";
	      }
	      else
	      {
		  if ( (compareVersion == V_NEWER ||
			compareVersion == V_EQUAL ) &&
		       buildTimeNew > buildTimeInstalled )
		  {
		      // udpate
		      modus = "u";
		  }
		  else
		  {
		      // do not know, what to do. --> ask user
		      modus = "m";
		  }
	      }
	  }
      }
      else
      {
	  // package is not in the current common.pkd
	  bool found = false;

	  // checking, if the package will be deleted by a rpm call of
	  // another package
	  for ( posObsoletes = obsoletesMap.begin();
		posObsoletes != obsoletesMap.end();
		++posObsoletes )
	  {
	      TagList tagList = posObsoletes->second;
	      TagList::iterator pos;

	      for ( pos = tagList.begin();
		    pos != tagList.end();
		    ++pos )
	      {
		  // each obsoletes entry
		  // Check, if this obsolte-entry is the installed package
		  if ( installedPackage.packageName == *pos )
		  {
		      found = true;
		      break;
		  }
	      }

	      if ( found )
	      {
		  break;
	      }
	  }

	  if ( !found )
	  {
	      // it must be a package which will not be deleted while update

	      // checking, if it is a SuSE package
	      string vendor = "";
	      YCPPath path = ".targetpkg.info.vendor";
	      YCPValue retScr = mainscragent->Read( path,
						    YCPString ( installedPackage.packageName ));
	      if ( retScr->isString() )	// success
	      {
		  vendor = retScr->asString()->value();
	      }

	      if ( vendor.find( SUSE ) != string::npos )
	      {
		  // It is a SuSE package which will not be longer supported
		  // and will not be deleted by package dependencies.
		  // So we will suggest it for deletion.
		  modus = "d";
	      }
	  }
      }

      if ( modus.length() > 0 )
      {
	 packages->add ( YCPString ( installedPackage.packageName ),
			 YCPString ( modus ) );
      }
   }


   ret->add ( YCPString ( PACKAGES ), packages );
   ret->add ( YCPString ( INSTALLEDVERSION ),
	      YCPString ( updateInfName ) );
   ret->add ( YCPString ( UPDATEVERSION),
	      YCPString ( infoName ) );
   ret->add ( YCPString ( UPDATEBASE ),
	      YCPBoolean ( updateBaseSystem ) );

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Compare the version of installed system with the version of install-medium.
 * Retunrn $["installedGreater": TRUE ,
 *  "installedVersion":"6.3",
 *  "updateVersion":"6.4.0"] if no equal; else $[]
 *--------------------------------------------------------------------------*/

YCPValue PackageAgent::compareSuSEVersions( const YCPString &to_install_version )
{
   YCPMap ret;
   ConfigFile updateInf ( yastPath + "/update.inf" );
   ConfigFile info ( packageInfoPath + "/info" );
   Entries entriesUpdateInf;
   Entries entriesInfo;
   string updateInfVersion;
   string infoVersion = to_install_version->value();

   y2debug( "CALLING compareSuSEVersions" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   if ( !update )
   {
      y2error( "Server not in update-modus" );
      return YCPVoid();
   }

   entriesUpdateInf.clear();
   updateInf.readFile ( entriesUpdateInf, " :" );
   entriesInfo.clear();
   info.readFile ( entriesInfo, " =" );

   Entries::iterator pos;


   // reading variables from /var/lib/YaST/update.inf

   pos = entriesUpdateInf.find ( DISTRIBUTIONVERSION );
   if ( pos != entriesUpdateInf.end() )
   {
      Values values = (pos->second).values;
      Values::iterator posValues;
      if ( values.size() >= 0 )
      {
	 posValues = values.begin();
	 updateInfVersion = *posValues;
      }
      else
      {
	 y2error( "Distribution_Version in update.inf not found" );
	 updateInfVersion = "";
      }
   }
   else
   {
      y2error( "Distribution_Version in update.inf not found" );
      updateInfVersion = "";
   }

   if ( infoVersion.size() <= 0 )
   {
      // reading variables from /var/adm/mount/suse/setup/descr/info

      pos = entriesInfo.find ( DISTIDENT );
      if ( pos != entriesInfo.end() )
      {
	 Values values = (pos->second).values;
	 Values::iterator posValues;
	 if ( values.size() >= 0 )
	 {
	    string infoName;
	    posValues = values.begin();
	    infoName = *posValues;

	    // Splitting DISTIDENT into Distribution-name, -version
	    // and release
	    string::size_type    firstSeperator, secondSeperator;

	    firstSeperator = infoName.find_last_of ( '-' );
	    secondSeperator = infoName.find_first_of ( '#' );
	    if ( firstSeperator != string::npos &&
		 secondSeperator != string::npos )
	    {
	       // Distribution_Version
	       infoVersion = infoName.substr ( firstSeperator+1,
					       secondSeperator -
					       firstSeperator - 1 );
	    }
	    else
	    {
	       y2error( "PRODUKT_VERSION in info not found" );
	       infoVersion = "";
	    }
	 }
	 else
	 {
	    y2error( "PRODUKT_VERSION in info not found" );
	    infoVersion = "";
	 }
      }
      else
      {
	 y2error( "PRODUKT_VERSION in info not found" );
	 infoVersion = "";
      }
   }

   CompareVersion compareVersion;
   compareVersion = CompVersion ( updateInfVersion.c_str(),
				  infoVersion.c_str() );

   if ( compareVersion != V_EQUAL )
   {
      if ( compareVersion == V_OLDER )
      {
	 ret->add ( YCPString ( INSTALLEDGREATER ),
		    YCPBoolean ( false ) );
      }
      else
      {
	 ret->add ( YCPString ( INSTALLEDGREATER ),
		    YCPBoolean ( true ) );
      }
      ret->add ( YCPString ( INSTALLEDVERSION ),
		 YCPString ( updateInfVersion ) );
      ret->add ( YCPString ( UPDATEVERSION),
		 YCPString ( infoVersion ) );
   }

   return ( ret );
}



/*--------------------------------------------------------------------------*
 * Evaluate the installed and CD-version of the distri and returns a map like:
 * $[ "installedVersion":"SuSE 6.3",
 *  "updateVersion":"SuSE 6.4" ]
 *--------------------------------------------------------------------------*/

YCPValue PackageAgent::readVersions(void)
{
   YCPMap ret;
   ConfigFile updateInf ( yastPath + "/update.inf" );
   ConfigFile info ( packageInfoPath + "/info" );
   Entries entriesUpdateInf;
   Entries entriesInfo;
   string updateInfName;
   string infoName;

   y2debug( "CALLING readVersions" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   entriesUpdateInf.clear();
   updateInf.readFile ( entriesUpdateInf, " :" );
   entriesInfo.clear();
   info.readFile ( entriesInfo, " =" );

   Entries::iterator pos;


   pos = entriesUpdateInf.find ( BASESYSTEM );
   if ( pos != entriesUpdateInf.end() )
   {
      Values values = (pos->second).values;
      Values::iterator posValues;
      if ( values.size() >= 0 )
      {
	 posValues = values.begin();
	 updateInfName = *posValues;
      }
      else
      {
	 y2error( "Basesystem in update.inf not found" );
	 updateInfName = "";
      }
   }
   else
   {
      y2error( "Basesystem in update.inf not found" );
      updateInfName = "";
   }

   // reading variables from /var/adm/mount/suse/setup/descr/info

   pos = entriesInfo.find ( DISTIDENT );
   if ( pos != entriesInfo.end() )
   {
      Values values = (pos->second).values;
      Values::iterator posValues;
      if ( values.size() >= 0 )
      {
	 posValues = values.begin();
	 infoName = *posValues;
      }
      else
      {
	 y2error( "DIST_IDENT in info not found" );
	 infoName = "";
      }
   }
   else
   {
      y2debug( "DIST_IDENT in info not found" );
      infoName = "";
   }

   ret->add ( YCPString ( INSTALLEDVERSION ),
	      YCPString ( updateInfName ) );
   ret->add ( YCPString ( UPDATEVERSION),
	      YCPString ( infoName ) );

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * compare two versions of a package
 *--------------------------------------------------------------------------*/
CompareVersion PackageAgent::CompVersion( string left,
						string right )
{
   string::size_type beginLeft,beginRight;

   if (  left == right )
   {
      y2debug( "---> is equal" );
      return V_EQUAL;
   }

   string leftString = "";
   string rightString = "" ;
   bool compareNumber = true;
   long leftNumber = -1;
   long rightNumber = -1;

   beginLeft = left.find_first_of ( ". -/" );
   beginRight = right.find_first_of ( ". -/" );

   if ( beginLeft != string::npos )
   {
      leftString = left.substr ( 0, beginLeft );
   }
   else
   {
      // last entry
      leftString = left;
   }
   if ( beginRight != string::npos )
   {
      rightString = right.substr ( 0, beginRight );
   }
   else
   {
      // last entry
      rightString = right;
   }

   if (  rightString.empty() && leftString.empty() )
   {
      y2debug( "---> is equal" );
      return V_EQUAL;
   }

   char *rest = NULL;

   leftNumber = strtol( leftString.c_str(), &rest, 10 );
   if ( rest != NULL && *rest != 0 )
   {
      compareNumber = false;
   }

   rightNumber = strtol( rightString.c_str(), &rest, 10 );
   if ( rest != NULL && *rest != 0)
   {
      compareNumber = false;
   }

   y2debug( "comparing #%s# <-> #%s#",
	    leftString.c_str(), rightString.c_str());

   if ( ( rightString.empty()  &&
	  leftNumber == 0 &&
	  beginLeft == string::npos) ||
	( leftString.empty() &&
	  rightNumber == 0 &&
	  beginRight == string::npos ) )
   {
      // evaluate like 7.0 and 7.0.0 --> equal
      y2debug( "---> is equal" );
      return V_EQUAL;
   }

   if ( ( rightString.empty()  && !leftString.empty() ) ||
	( compareNumber && leftNumber>rightNumber ) ||
	( !compareNumber && leftString > rightString ) )
   {
      y2debug( "---> is newer" );
      return V_NEWER;
   }

   if (( !rightString.empty() && leftString.empty() ) ||
	( compareNumber && leftNumber<rightNumber ) ||
	( !compareNumber && leftString < rightString ) )
   {
      y2debug( "---> is older" );
      return V_OLDER;
   }

   if ( rightString == leftString )
   {
      string dummy1,dummy2;

      if ( beginLeft != string::npos )
      {
	 dummy1 = left.substr( beginLeft +1 );
      }
      else
      {
	 dummy1 = "";
      }

      if ( beginRight != string::npos )
      {
	 dummy2 = right.substr ( beginRight +1 );
      }
      else
      {
	 dummy2 = "";
      }

      if ( !dummy1.empty() && !dummy2.empty() )
      {
	 string sepLeft = left.substr( beginLeft,1 );
	 string sepRight = right.substr( beginRight,1 );

	 // checking if dummy2 is revision-number and dummy1
	 // is not a revistion-number
	 if ( sepLeft == "." &&
	      sepRight == "-" )
	 {
	    y2debug( "left is no revision---> is newer" );
	    return V_NEWER;
	 }

	 if ( sepLeft == "-" &&
	      sepRight == "." )
	 {
	    y2debug( "right is no revision---> is older" );
	    return V_OLDER;
	 }
      }

      return CompVersion( dummy1, dummy2);
   }

  y2debug( "---> do not know" );

  return V_UNCOMP;
}

/*--------------------------- EOF -------------------------------------------*/
