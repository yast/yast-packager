/*************************************************************
 *
 *     YaST2      SuSE Labs                        -o)
 *     --------------------                        /\\
 *                                                _\_v
 *           www.suse.de / www.suse.com
 * ----------------------------------------------------------
 *
 * File:	  PackageCalls.cc
 *
 * Author: 	  Stefan Schubert <schubi@suse.de>
 *
 * Description:   Calls for agent "package". Resolve package-dependencies and
 *		  calkulate disk-spaces.
 *
 * $Header$
 *
 *************************************************************/


#include <locale.h>
#include <libintl.h>
#include <stdlib.h>
#include <config.h>
#include <sys/stat.h>
#include <unistd.h>

#include "PackageAgent.h"
#include <scr/SCRAgent.h>
#include <scr/SCRInterpreter.h>
#include <Y2.h>
#include <YCP.h>
#include <ycp/y2log.h>
#include <pkg/ConfigFile.h>


/*-------------------------------------------------------------*/
/* Create all parent directories of @param name, as necessary  */
/*-------------------------------------------------------------*/
static void
create_directories(string name)
{
  size_t pos = 0;

  while (pos = name.find('/', pos + 1), pos != string::npos)
    mkdir (name.substr(0, pos).c_str(), 0777);
}



/***************************************************************************
 * Private Member-Functions						   *
 ***************************************************************************/

/*------------------------------------------------------------------------*
 * Initialize the agent with the environment delivered by the setMap:
 * $["update":TRUE,
 *   "packetinfopath":"/mnt/suse/setup/desc",
 *   "language":"german",
 *   "common.pkd":"common.pkd",
 *   "dudir":"/mnt/suse/setup/du/du.dir",
 *   "partition":[$["name":"/","used":0,"free":1500],
 *	  	     $["name":"var","used":0,"free":100000]]
 *    "rootpath":"/",
 *   "yastpath":"/var/lib/YaST",
 *   "memoptimized":TRUE,
 *   "forceInit": FALSE]
 *          SIZE is kByte !!!!
 *------------------------------------------------------------------------*/

static YCPMap compareMap;	// don't move into function, g++ bug

YCPValue PackageAgent::setEnvironment ( YCPMap setMap )
{
   YCPBoolean ok ( true );
   YCPValue dummyValue = YCPVoid();
   bool forceInit = false;
   string savePackageInfoPath = "";
   string saveLanguage = "";
   string saveCommonPkd = "";
   bool initPkg = false;

   y2debug( "CALLING setEnvironment");

   dummyValue = setMap->value(YCPString(FORCEINIT));
   if ( !dummyValue.isNull() && dummyValue->isBoolean() )
   {
      forceInit = dummyValue->asBoolean()->value();
      if ( forceInit )
      {
	y2debug( "setEnvironment: forceInit = true");
      }
      else
      {
	y2debug( "setEnvironment: forceInit = false");
      }
   }
   else
   {
	y2debug( "setEnvironment: DEFAULT forceInit = false");
   }

   if ( !forceInit &&
	rawPackageInfo != NULL &&
	compareMap->compare(setMap)==YO_EQUAL )
   {
      y2debug( "setEnvironment() was called more than once times --> no init");
      return ok;
   }

   // evaluate saved variables
   dummyValue = compareMap->value(YCPString(PACKAGEINFOPATH));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
      savePackageInfoPath = dummyValue->asString()->value();
      y2debug( "setEnvironment: savePacketinfopath = %s", savePackageInfoPath.c_str() );
   }
   dummyValue = compareMap->value(YCPString(COMMONPKD));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
      saveCommonPkd = dummyValue->asString()->value();
      y2debug( "setEnvironment: SaveCommon.pkd = %s", saveCommonPkd.c_str() );
   }
   dummyValue = compareMap->value(YCPString(LANGUAGE));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
      saveLanguage = dummyValue->asString()->value();
      y2debug( "setEnvironment: saveLanguage = %s", saveLanguage.c_str() );
   }


   // resolve current parameters

   dummyValue = setMap->value(YCPString(PACKAGEINFOPATH));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
      packageInfoPath = dummyValue->asString()->value();
      y2debug( "setEnvironment: packetinfopath = %s",packageInfoPath.c_str() );
   }
   else
   {
      packageInfoPath = "";
      y2error( "PACKAGEINFOPATH not found" );

      ok = false;
   }

   dummyValue = setMap->value(YCPString(ROOTPATH));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
      rootPath = dummyValue->asString()->value();
      y2debug( "setEnvironment: rootpath = %s",rootPath.c_str() );
   }
   else
   {
      rootPath = "";
      y2debug( "ROOTPATH not found" );
   }

   dummyValue = setMap->value(YCPString(YASTPATH));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
      yastPath = dummyValue->asString()->value();
      y2debug( "setEnvironment: yastpath = %s",yastPath.c_str() );
   }
   else
   {
      yastPath = "";
      y2debug( "YASTPATH not found" );
   }

   dummyValue = setMap->value(YCPString(COMMONPKD));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
      commonPkd = dummyValue->asString()->value();
      y2debug( "setEnvironment: common.pkd = %s",commonPkd.c_str() );
   }
   else
   {
      y2error( "COMMON.PKD not found -> default" );
   }


   dummyValue = setMap->value(YCPString(LANGUAGE));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
      language = dummyValue->asString()->value();
      y2debug( "setEnvironment: language = %s",language.c_str() );
   }
   else
   {
      language = "";
      y2error ( "LANGUAGE  not found" );
      ok = false;
   }

   dummyValue = setMap->value(YCPString(MEMOPTIMIZED));
   if ( !dummyValue.isNull() && dummyValue->isBoolean() )
   {
       y2debug( "setEnvironment:  memoryOptimized has been ALWAYS activated");
   }

   dummyValue = setMap->value(YCPString(UPDATEMODE));
   if ( !dummyValue.isNull() && dummyValue->isBoolean() )
   {
      update = dummyValue->asBoolean()->value();
      if ( update )
      {
	y2milestone( "setEnvironment: update = true");
      }
      else
      {
	y2milestone( "setEnvironment: update = false");
      }
   }
   else
   {
	y2milestone( "setEnvironment: DEFAULT update = false");
	update = false;
   }

   if ( ok->value() &&
	( savePackageInfoPath != packageInfoPath ||
	  saveLanguage != language ||
	  saveCommonPkd != commonPkd ||
	  forceInit ))
   {
      initPkg = true;

      if ( rawPackageInfo != NULL )
      {
	 // release old
	 delete rawPackageInfo;
	 rawPackageInfo = NULL;
      }
      // Reading new packet-information
      rawPackageInfo = new RawPackageInfo ( packageInfoPath,
					    language, commonPkd, true );
   }


   PartitionList partitionList; // Desired partition while reading du.dir

   if ( ok->value() )
   {
      // Reading partition sizes
      dummyValue = setMap->value(YCPString(PARTITION));
      if ( !dummyValue.isNull() && dummyValue->isList() )
      {
	 YCPList list = dummyValue->asList();
	 int counter;
	 y2debug( "setEnvironment: Partitions:");

	 partitionSizeMap.clear(); // delete old stuff
	 for ( counter = 0; counter<list->size(); counter++ )
	 {
	    if ( list->value(counter)->isMap() )
	    {
	       YCPMap partition = list->value(counter)->asMap();
	       SizeInfo sizeInfo = {0,0};
	       string name = "";
	       YCPValue dummy = YCPVoid();

	       dummy = partition->value(YCPString(NAME));
	       if ( !dummy.isNull() && dummy->isString() )
	       {
		  name = dummy->asString()->value();
		  partitionList.insert ( name );
	       }
	       dummy = partition->value(YCPString(USED));
	       if ( !dummy.isNull() && dummy->isInteger() )
	       {
		  sizeInfo.used = dummy->asInteger()->value();
	       }
	       dummy = partition->value(YCPString(FREE));
	       if ( !dummy.isNull() && dummy->isInteger() )
	       {
		  sizeInfo.free = dummy->asInteger()->value();
	       }
	       y2debug("setEnvironment:            %s USED %d FREE %d",
		     name.c_str(),sizeInfo.used,sizeInfo.free);

	       // insert in map
	       partitionSizeMap.insert(pair<const string, SizeInfo>(
						name,
						sizeInfo ));
	    }
	 }
      }
      else
      {
	 y2warning( "Partition-map not found" );
      }
   }

   dummyValue = setMap->value(YCPString(DUDIR));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
      duDir = dummyValue->asString()->value();
      y2debug( "setEnvironment: duDir = %s",duDir.c_str() );
   }
   else
   {
      duDir = "";
      y2error( "DUDIR  not found" );
      ok = false;
   }

   if ( ok->value() )
   {
      // Reading package-sizes
      rawPackageInfo->readRawPackageInstallationSize ( duDir,
						       partitionList);
   }

   //	initialize targetpkg agent if update
   if ( ok->value() && update )
   {

       readInstalledPackages( instPackageMap );
   }


   if ( ok->value() && initPkg )
   {
      // get Package-list from common.pkd
      packageInstallMap.clear(); // delete old stuff
      PackVersList packageList = rawPackageInfo->getRawPackageList( true );
      PackVersList::iterator pos;

      y2debug( "setEnvironment: Packages:");
      for ( pos = packageList.begin(); pos != packageList.end(); ++pos )
      {
	 PackageKey packageKey = *pos;
	 InstallSelection installSelection = {false,NONE,NO,false};
	 if ( update )
	 {
	    // checking if the package is installed.
	    InstPackageMap::iterator posPackage = instPackageMap.find(
							packageKey.name());
	    if ( posPackage != instPackageMap.end() )
	    {
	       installSelection.isInstalled = true;
	    }
	 }
	 // insert in map
	 packageInstallMap.insert(pair<const string, InstallSelection>(
							   packageKey.name(),
							   installSelection ));
      }

      // get selection list from suse/sutup/descr/*.sel */
      SelectionGroupMap groupMap;
      SelectionGroupMap::iterator selpos;

      selInstallMap.clear(); // delete old stuff
      rawPackageInfo->getSelectionGroupMap ( groupMap );;
      y2debug( "setEnvironment: Selections:");
      for ( selpos = groupMap.begin(); selpos != groupMap.end(); ++selpos )
      {
	 SelectionGroup	 selectionGroup = selpos->second;

	 SelInstallSelection installSelection = {false,"",NO,0};

	 installSelection.visible = selectionGroup.visible;
	 installSelection.kind = selectionGroup.kind;
	 // insert in map
	 selInstallMap.insert(pair<const string, SelInstallSelection>(
						selpos->first,
						installSelection ));
	 y2debug( "setEnvironment:       %s",(selpos->first).c_str() );
      }

      // Solver

      if ( solver != NULL )
      {
	 // remove old stuff
	 delete solver;
	 solver = NULL;
      }

      if ( selSolver != NULL )
      {
	 // remove old stuff
	 delete selSolver;
	 selSolver = NULL;
      }


      if ( rawPackageInfo != NULL )
      {

	 PackVersList	packageList;
	 PackTagLMap    providesDependencies;
	 PackTagLMap    obsoletesDependencies;
	 PackDepLMap    requiresDependencies;
	 PackDepLMap    conflictsDependencies;
	 PackVersList	emptyList;

	 // evaluate all packages which are on the system but no longer
	 // in the common.pkd
	 InstPackageMap::iterator posPackage;

	 for ( posPackage = instPackageMap.begin();
	       posPackage != instPackageMap.end();
	       posPackage++ )
	 {
	     PackageInstallMap::iterator pos = packageInstallMap.find ( posPackage->first );
	     if ( pos == packageInstallMap.end() )
	     {
		 // no longer in the common.pkd
		 TagList tagList;
		 InstPackageElement packageElement = posPackage->second;
		 PackageKey packageKey ( posPackage->first, packageElement.version );
		 y2debug ( "Package %s version %s no longer in the common.pkd --> insert into solver",
			   (posPackage->first).c_str(),
			   (packageElement.version).c_str() );
		 packageList.push_back( packageKey );
		 tagList.insert ( posPackage->first );
		 providesDependencies.insert(pair<PackageKey,
					     TagList>( packageKey,
						       tagList ));

		 // insert this unsopported package into the packagelist, which will shown the user
		 InstallSelection installSelection = {true,NONE,NO,true};

		 packageInstallMap.insert(pair<const string, InstallSelection>(
									       posPackage->first,
									       installSelection ));

	     }
	 }

	 //package stuff
	 solver = new Solver( rawPackageInfo,
			      requiresDependencies,
			      conflictsDependencies,
			      providesDependencies,
			      obsoletesDependencies,
			      packageList );

	 // selection stuff
	 packageList.clear();
	 providesDependencies.clear();
	 obsoletesDependencies.clear();
	 requiresDependencies.clear();
	 conflictsDependencies.clear();
	 emptyList.clear();

	 packageList = rawPackageInfo->getSelectionList();
	 providesDependencies = rawPackageInfo->getSelProvidesDependency();
	 obsoletesDependencies.clear();
	 requiresDependencies = rawPackageInfo->getSelRequiresDependency();
	 conflictsDependencies = rawPackageInfo->getSelConflictsDependency();

	 selSolver = new Solver( requiresDependencies,
				 conflictsDependencies,
				 providesDependencies,
				 obsoletesDependencies,
				 packageList,
				 emptyList );
      }

      if ( update )
      {
	 // Initialize solver with installed packages
	 PackVersList solverList;
	 PackageInstallMap::iterator posInstallMap;

	 for ( posInstallMap = packageInstallMap.begin();
	       posInstallMap != packageInstallMap.end();
	       posInstallMap++ )
	 {
	    InstallSelection *installSelection = &(posInstallMap->second);

	    // insert into solverList, because this package
	    // is installed
	    if ( installSelection->isInstalled )
	    {
	       string version = getVersion (posInstallMap->first, true);

	       PackageKey packageKey ( posInstallMap->first, version );

	       solverList.push_back ( packageKey );
	    }
	 }

	 // adding strange packages
	 addStrangePackages ( solverList );

	 // setting solver

	 solver->SolveDependencies( solverList,
				    additionalPackages,
				    unsolvedRequirements,
				    conflictMap,
				    obsoleteMap );
      }
   }

   // saving parameters for next call
   compareMap = setMap;

   if ( rawPackageInfo && !rawPackageInfo->numPackages() ) {
     y2error( "No packages found on install medium" );
     ok = false;
   }

   if ( ok->value() )
   {
      y2debug( "setEnvironment: RETURN TRUE");
   }
   else
   {
      y2debug( "setEnvironment: RETURN FALSE");
   }

   return ( ok );
}

/*-------------------------------------------------------------------------*
 * Reads all packet-informations which are described in common.pkd.
 * Returns a map like
 * $["aaa_base":["SuSE Linux Verzeichnisstruktur", "X", 378,<version> ],
 *    "aaa_dir",[...],...]</td></tr>
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::getPackageList( void )
{
   YCPMap  ret;
   PackList sourcePackageList;

   y2debug( "CALLING getPackageList" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   sourcePackageList = rawPackageInfo->getSourcePackages();

   PackageInstallMap::iterator pos;
   for ( pos = packageInstallMap.begin(); pos != packageInstallMap.end();
	 ++pos)
   {
      // each package in common.pkd
      string shortDescription = "";
      string longDescription = "";
      string notify = "";
      string delDescription = "";
      string category = "";
      int size = 0;
      string status = "";
      bool isSource = false;
      bool basePackage;
      int installationPosition;
      int cdNr;
      string instPath;
      long buildTime;
      int rpmSize;
      string version;

      YCPList list;

      InstallSelection installSelection = pos->second;

      if ( installSelection.foreignPackage )
      {
	  // not know package --> getting description via rpm
	  YCPPath path = ".targetpkg.info.summary";
	  YCPValue retScr = mainscragent->Read( path,
						YCPString ( (string) pos->first ));
	  if ( retScr->isString() )	// success
	  {
	      shortDescription = retScr->asString()->value();
	  }
      }
      else
      {
	  // get information from the common.pkd
	  rawPackageInfo->getRawPackageDescritption( (string) pos->first,
						 shortDescription,
						 longDescription,
						 notify,
						 delDescription,
						 category,
						 size);
	  rawPackageInfo->getRawPackageInstallationInfo(
						    (string) pos->first,
						    basePackage,
						    installationPosition,
						    cdNr,
						    instPath,
						    version,
						    buildTime,
						    rpmSize);
      }

      // Check if the package is a source-package
      PackList::iterator posSourcePackageList =
	 sourcePackageList.find ( (string) pos->first );
      if ( posSourcePackageList != sourcePackageList.end() )
      {
	 isSource = true;
      }

      if ( !isSource )
      {
	 if ( containsPackage ( additionalPackages, (string)pos->first )  )
	 {
	    // automatik
	    status = "a";
	 }

	 if ( installSelection.isInstalled )
	 {
	    status = "i";
	 }
	 switch ( installSelection.action )
	 {
	    case INSTALL:
	       status = "X";
	       break;
	    case DELETE:
	       status = "d";
	       break;
	    case UPDATE:
	       status = "u";
	       break;
	    default:
	       break;
	 }

	 y2debug( "getPackageList: NAME        %s",
		((string) pos->first ).c_str() );

	 list->add( YCPString (shortDescription ));
	 y2debug( "getPackageList: DESCRIPTION %s",
	    shortDescription.c_str() );
	 list->add ( YCPString ( status ) );
	 list->add ( YCPInteger ( size ) );
	 list->add ( YCPString ( version ) );

	 ret->add( YCPString( (string) pos->first ),
		list );
      }
   }

   return ( ret );
}


/*-------------------------------------------------------------------------*
 *  Check, if an update has not been successfully
 * Returns a map of packages which have to be installed or delete success
 * fully:
 * $["aaa_base":"u", "at":"d", ......]
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::checkBrokenUpdate( void )
{
   YCPMap  ret;
   ConfigFile installLst ( yastPath + "/install.lst" );
   Entries entries;

   y2debug( "CALLING checkBrokenUpdate" );

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

   entries.clear();
   Values deleteValues;
   Element deleteElement;
   deleteElement.values = deleteValues;
   deleteElement.multiLine = true;
   Values insertValues;
   Element insertElement;
   insertElement.values = insertValues;
   insertElement.multiLine = true;

   entries.insert(pair<const string, const Element>
		  ( TODELETE, deleteElement ) );
   entries.insert(pair<const string, const Element>
		  ( TOINSTALL, insertElement ) );

   installLst.readFile ( entries, " :" );

   Entries::iterator pos;

   pos = entries.find ( TODELETE );
   if ( pos != entries.end() );
   {
      Values values = (pos->second).values;
      Values::iterator posValues;
      for ( posValues = values.begin(); posValues != values.end() ;
	    ++posValues )
      {
	 ret->add ( YCPString ( *posValues ), YCPString ( "d" ) );
      }
   }

   pos = entries.find ( TOINSTALL );
   if ( pos != entries.end() );
   {
      Values values = (pos->second).values;
      Values::iterator posValues;
      for ( posValues = values.begin(); posValues != values.end() ;
	    ++posValues )
      {
	 ret->add ( YCPString ( *posValues ), YCPString ( "u" ) );
      }
   }

   return ( ret );
}



/*-------------------------------------------------------------------------*
 * Evaluate a branch of the package-tree.
 * Parameter : $["branch":<branch>, "rpmgroup":true]
 * If branch is NULL the contents of map are the series.
 * If branch is the Name of a serie, the return value is a
 * list of all packages which belongs to the serie.
 * If rpmgroup is true rpmgroups are handled instead of series.
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::getHierarchyInformation( const YCPMap &branchMap )
{
   YCPMap map;
   PackList::iterator pos;
   PackList serieList;
   PackList sourcePackageList;
   YCPString branch("");
   YCPBoolean rpmgroup(false);
   YCPValue dummyValue = YCPVoid();

   dummyValue = branchMap->value(YCPString(BRANCH));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
       branch  = dummyValue->asString();
   }
   else
   {
       branch = YCPString( "" );
   }

   dummyValue = branchMap->value(YCPString(RPMGROUP));
   if ( !dummyValue.isNull() && dummyValue->isBoolean() )
   {
       rpmgroup = dummyValue->asBoolean();
   }
   else
   {
       rpmgroup = YCPBoolean( false );
   }

   bool group = rpmgroup->value();

   y2debug( "CALLING getHierarchyInformation" );

   if ( rawPackageInfo == NULL )
   {
      y2error ( "missing call setEnvironment()");
      return YCPVoid();
   }

   if ( branch->value().empty() )
   {
      if ( group )
      {
	 // return the map of rpmgroups
	 serieList = rawPackageInfo->getAllRpmgroup();
      }
      else
      {
	 // return the map of series
	 serieList = rawPackageInfo->getAllSeries();
      }
      y2debug( "     Branch: NULL" );
   }
   else
   {
      // return a map of packages
      if ( group )
      {
	 serieList = rawPackageInfo->getRawPackageListOfRpmgroup(
							branch->value() );
      }
      else
      {
	 serieList = rawPackageInfo->getRawPackageListOfSerie(
							branch->value() );
      }
      y2debug( "     Branch: %s",(branch->value()).c_str() );
   }

   if ( installSources )
   {
      sourcePackageList = rawPackageInfo->getSourcePackages();
   }
   else
   {
      sourcePackageList.clear();
   }

   y2debug( "getHierarchyInformation: PACKAGES:" );

   for ( pos = serieList.begin(); pos != serieList.end(); ++pos )
   {
      string shortDescription = "";
      string longDescription = "";
      string notify = "";
      string delDescription = "";
      string category = "";
      string status = "";
      int size = 0;
      bool basePackage;
      int installationPosition;
      int cdNr;
      string instPath;
      long buildTime;
      int rpmSize;
      string version;

      YCPList list;

      if ( !branch->value().empty() )
      {
	 // return the map of packages
	 PackageInstallMap::iterator posPackage;

	 rawPackageInfo->getRawPackageDescritption( (string) *pos,
						    shortDescription,
						    longDescription,
						    notify,
						    delDescription,
						    category,
						    size);
	 rawPackageInfo->getRawPackageInstallationInfo(
						    (string) *pos,
						    basePackage,
						    installationPosition,
						    cdNr,
						    instPath,
						    version,
						    buildTime,
						    rpmSize);

	 posPackage = packageInstallMap.find ( *pos );
	 if ( posPackage != packageInstallMap.end() )
	 {
	    // entry found
	    InstallSelection installSelection = posPackage->second;

	    if ( installSources )
	    {
	       // Check if the package is a source-package and
	       // if it is not deselected by the user
	       PackList::iterator posSourcePackageList =
		  sourcePackageList.find ( *pos );
	       if ( posSourcePackageList != sourcePackageList.end() &&
		    installSelection.singleSelect != INSTALL_DESELECTED &&
		    installSelection.singleSelect != DELETE_SELECTED &&
		    installSelection.singleSelect != UPDATE_SELECTED )
	       {
		  status = "X";
	       }
	    }

	    if ( containsPackage ( additionalPackages, *pos ) )
	    {
	       // automatik
	       status = "a";
	    }

	    if ( installSelection.isInstalled )
	    {
	       status = "i";
	    }
	    switch ( installSelection.action )
	    {
	       case INSTALL:
		  status = "X";
		  break;
	       case DELETE:
		  status = "d";
		  break;
	       case UPDATE:
		  status = "u";
		  break;
	       default:
		  break;
	    }
	 }
      }

      list->add ( YCPString ( shortDescription ) );
      list->add ( YCPString ( status ) );
      list->add ( YCPInteger ( size ) );
      list->add ( YCPString ( version ) );

      map->add ( YCPString ( *pos ),list );
      y2debug( "getHierarchyInformation:      %s",
	     ((string)*pos).c_str());
   }

   return ( map );
}

/*-------------------------------------------------------------------------*
 * Set the list of packets which have to be installed.
 * a is the list of packages which have to be installed. Every other
 * set is deleted
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::setInstallSelection(const YCPList &packageList,
						 bool notResetSingleSelected )
{
   PackVersList solverList;
   PackageInstallMap::iterator posInstallMap;
   YCPBoolean ret ( true );

   y2debug( "CALLING setInstallSelection" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   // deselect all

   installSources = false;

   for ( posInstallMap = packageInstallMap.begin();
	 posInstallMap != packageInstallMap.end();
	 posInstallMap++ )
   {
      InstallSelection *installSelection = &(posInstallMap->second);
      if ( !notResetSingleSelected )
      {
	 // reset all settings
	 installSelection->action = NONE;
	 installSelection->singleSelect = NO;
      }
      else
      {
	 if ( installSelection->singleSelect == INSTALL_SELECTED )
	 {
	    installSelection->action = INSTALL;
	 }
	 else
	 {
	    if ( installSelection->action == INSTALL ||
		 installSelection->action == UPDATE )
	    {
	       installSelection->action = NONE;
	    }
	 }
      }

      // insert into solverList, because this package was
      // selected to install, update or is installed
      if ( !installSelection->foreignPackage
	   && ( installSelection->action == INSTALL ||
		installSelection->action == UPDATE ||
		( installSelection->isInstalled &&
		  installSelection->action != DELETE )))
      {
	 string version;
	 if ( installSelection->action == INSTALL ||
	      installSelection->action == UPDATE )
	 {
	    // new version from the common.pkd
	    version = getVersion ( posInstallMap->first, false );
	 }
	 else
	 {
	    // package has been installed, but will not be
	    // changed
	    version = getVersion ( posInstallMap->first, true );
	 }

	 PackageKey packageKey ( posInstallMap->first, version );

	 solverList.push_back ( packageKey );
      }
   }

   // select toInstall
   y2debug( "setInstallSelection: selected packages" );
   int counter;
   for ( counter = 0; counter < packageList->size(); counter++ )
   {
      if ( packageList->value(counter)->isString() )
      {
	 string packageName(
		packageList->value(counter)->asString()->value() );
	 posInstallMap = packageInstallMap.find( packageName );
	 if ( posInstallMap != packageInstallMap.end() )
	 {
	    InstallSelection *installSelection = &(posInstallMap->second);
	    if ( installSelection->singleSelect != INSTALL_DESELECTED )
	    {
	       installSelection->action = INSTALL;

	       // insert solverList
	       if ( !containsPackage( solverList, packageName ) )
	       {
		  // not found -->insert
		  string version;
		  version = getVersion ( packageName, false );

		  PackageKey packageKey ( packageName, version );
		  solverList.push_back ( packageKey );
	       }
	       y2debug( "setInstallSelection:         %s",
		      packageName.c_str());
	    }
	    else
	    {
	       y2debug( "setInstallSelection:         %s was single deselected",
		      packageName.c_str());
	    }
	 }
	 else
	 {
	    y2warning( "package %s not found",
		       packageName.c_str() );
	    ret = false;
	 }
      }
      else
      {
	 y2warning( "List has no string values" );
	 ret = false;
      }
   }

   // adding strange packages
   addStrangePackages ( solverList );

   // setting solver
   solver->SolveDependencies( solverList,
			      additionalPackages,
			      unsolvedRequirements,
			      conflictMap,
			      obsoleteMap );

   if ( ret->value() )
   {
      y2debug( "setInstallSelection: RETURN TRUE");
   }
   else
   {
      y2debug( "setInstallSelection: RETURN FALSE");
   }

   return ( ret );
}

/*--------------------------------------------------------------------------*
 * Set the list of packets which have to be deleted.
 * a is the list of packages which have to be removed. Every other
 * remove-set is deleted.
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::setDeleteSelection(const YCPList &packageList)
{
   PackVersList solverList;
   PackageInstallMap::iterator posInstallMap;
   YCPBoolean ret ( true );

   y2debug( "CALLING setDeleteSelection" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   // deselect all
   for ( posInstallMap = packageInstallMap.begin();
	 posInstallMap != packageInstallMap.end();
	 posInstallMap++ )
   {
      InstallSelection *installSelection = &(posInstallMap->second);
      if ( installSelection->action == DELETE )
      {
	 installSelection->action = NONE;
      }
      if ( installSelection->singleSelect == DELETE_SELECTED ||
	   installSelection->singleSelect == DELETE_DESELECTED )
      {
	 installSelection->singleSelect = NO;
      }

      // insert solverList
      if ( !installSelection->foreignPackage
	   && (( installSelection->isInstalled &&
		installSelection->action != DELETE )
	        || installSelection->action == INSTALL
	        || installSelection->action == UPDATE ))
      {
	 string version;
	 if ( installSelection->action == INSTALL ||
	      installSelection->action == UPDATE )
	 {
	    // new version from the common.pkd
	    version = getVersion ( posInstallMap->first, false );
	 }
	 else
	 {
	    // package has been installed, but will not be
	    // changed
	    version = getVersion ( posInstallMap->first, true );
	 }

	 PackageKey packageKey ( posInstallMap->first, version );

	 solverList.push_back ( packageKey );
      }
   }

   // select toDelete
   y2debug( "setDeleteSelection: to delete packages" );

   int counter;
   for ( counter = 0; counter < packageList->size(); counter++ )
   {
      if ( packageList->value(counter)->isString() )
      {
	 string packageName(
			    packageList->value(counter)->asString()->value() );
	 posInstallMap = packageInstallMap.find( packageName );
	 if ( posInstallMap != packageInstallMap.end() )
	 {
	    InstallSelection *installSelection = &(posInstallMap->second);
	    installSelection->action = DELETE;

	    PackVersList::iterator pos = posPackage( solverList, packageName );
	    // delete from  solverList
	    if ( pos != solverList.end() )
	    {
	       // found -->remove
	       solverList.erase( pos );
	    }
	    y2debug( "setDeleteSelection:         %s",
		   packageName.c_str());
	 }
	 else
	 {
	    y2warning( "package %s not found",
		       packageName.c_str() );
	    ret = false;
	 }
      }
      else
      {
	 y2warning( "List has no string values" );
	 ret = false;
      }
   }

   // adding strange packages
   addStrangePackages ( solverList );

   // setting solver
   solver->SolveDependencies( solverList,
			      additionalPackages,
			      unsolvedRequirements,
			      conflictMap,
			      obsoleteMap );

   if ( ret->value() )
   {
      y2debug( "setDeleteSelection: RETURN TRUE");
   }
   else
   {
      y2debug( "setDeleteSelection: RETURN FALSE");
   }

   return ( ret );
}



/*--------------------------------------------------------------------------*
 * Set the list of packets which have to be updated.
 * a is the list of packages which have to be updated. Every other
 * remove-set is deleted.
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::setUpdateSelection(const YCPList &packageList)
{
   PackVersList solverList;
   PackageInstallMap::iterator posInstallMap;
   YCPBoolean ret ( true );

   y2debug( "CALLING setUpdateSelection" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   // deselect all
   for ( posInstallMap = packageInstallMap.begin();
	 posInstallMap != packageInstallMap.end();
	 posInstallMap++ )
   {
      InstallSelection *installSelection = &(posInstallMap->second);
      if ( installSelection->action == UPDATE )
      {
	 installSelection->action = NONE;
      }
      if ( installSelection->singleSelect == UPDATE_SELECTED ||
	   installSelection->singleSelect == UPDATE_DESELECTED )
      {
	 installSelection->singleSelect = NO;
      }

      // insert solverList
      if ( !installSelection->foreignPackage
	   && (( installSelection->isInstalled &&
	     installSelection->action != DELETE )||
	   installSelection->action == INSTALL ||
	   installSelection->action == UPDATE ))
      {
	 string version;

	 if ( installSelection->action == INSTALL ||
	      installSelection->action == UPDATE )
	 {
	    // new version from the common.pkd
	    version = getVersion ( posInstallMap->first, false );
	 }
	 else
	 {
	    // package has been installed, but will not be
	    // changed
	    version = getVersion ( posInstallMap->first, true );
	 }

	 PackageKey packageKey ( posInstallMap->first, version );

	 solverList.push_back ( packageKey );
	 y2debug( "not changed package:         %s %s",
		  packageKey.name().c_str(), version.c_str());
      }
   }

   // select to Update
   y2debug( "setUpdateSelection:  packages to update" );

   int counter;
   for ( counter = 0; counter < packageList->size(); counter++ )
   {
      if ( packageList->value(counter)->isString() )
      {
	 string packageName(
			    packageList->value(counter)->asString()->value() );
	 posInstallMap = packageInstallMap.find( packageName );
	 if ( posInstallMap != packageInstallMap.end() )
	 {
	    InstallSelection *installSelection = &(posInstallMap->second);
	    installSelection->action = UPDATE;

	    y2debug( "setUpdateSelection: checking   %s ",
		     packageName.c_str());

	    // insert solverList
	    if ( !containsPackage( solverList, packageName ) )
	    {
	       // not found -->insert
	       string version;
	       version = getVersion ( packageName, false );

	       PackageKey packageKey ( packageName, version );
	       solverList.push_back ( packageKey );
	       y2debug( "setUpdateSelection:         %s %s",
			packageName.c_str(), version.c_str());
	    }
	 }
	 else
	 {
	    y2warning( "package %s not found",
		       packageName.c_str() );
	    ret = false;
	 }
      }
      else
      {
	 y2warning( "List has no string values" );
	 ret = false;
      }
   }

   // adding strange packages
   addStrangePackages ( solverList );

   // setting solver
   solver->SolveDependencies( solverList,
			      additionalPackages,
			      unsolvedRequirements,
			      conflictMap,
			      obsoleteMap );

   if ( ret->value() )
   {
      y2debug( "setUpdateSelection: RETURN TRUE");
   }
   else
   {
      y2debug( "setUpdateSelection: RETURN FALSE");
   }

   return ( ret );
}




/*--------------------------------------------------------------------------*
 * Set a package to install
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::selectInstall(const YCPString &packageName,
					   const YCPBoolean automatic )
{
   YCPBoolean ret ( true );
   PackageInstallMap::iterator posInstallMap;

   y2debug( "CALLING selectInstall" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   posInstallMap = packageInstallMap.find( packageName->value() );
   if ( posInstallMap != packageInstallMap.end() )
   {
      InstallSelection *installSelection = &(posInstallMap->second);
      installSelection->action = INSTALL;
      if ( !(automatic->value()) )
	 installSelection->singleSelect = INSTALL_SELECTED;
   }
   else
   {
      y2warning( "Package %s not found",
		 (packageName->value()).c_str() );
      ret = false;
   }

   // solve dependencies
   bool basePackage;
   int installationPosition;
   int cdNr;
   string instPath;
   long buildTime;
   int rpmSize;
   string version;

   rawPackageInfo->getRawPackageInstallationInfo(
						 packageName->value(),
						 basePackage,
						 installationPosition,
						 cdNr,
						 instPath,
						 version,
						 buildTime,
						 rpmSize);

   PackageKey packageKey ( packageName->value(), version );

   solver->AddPackage( packageKey,
		       additionalPackages,
		       unsolvedRequirements,
		       conflictMap,
		       obsoleteMap );

   if ( ret->value() )
   {
      y2debug( "selectInstall: RETURN TRUE");
   }
   else
   {
      y2debug( "selectInstall: RETURN FALSE");
   }

   return ( ret );
}



/*--------------------------------------------------------------------------*
 * Set a selection to install
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::selectSelInstall(const YCPString &selName,
					      const YCPBoolean reset )
{
   YCPBoolean ret ( true );
   SelInstallMap::iterator posInstallMap;

   y2debug( "CALLING selectSelInstall" );
   y2debug( "         selection : %s", (selName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   if ( reset->value() )
   {
      for ( posInstallMap = selInstallMap.begin();
	    posInstallMap != selInstallMap.end();
	    posInstallMap++ )
      {
	 SelInstallSelection *installSelection = &(posInstallMap->second);
	 installSelection->singleSelect = NO;
      }

      // reset solver
      PackVersList   selVersList;
      selVersList.clear();

      selSolver->SolveDependencies( selVersList,
				    selAdditionalPackages,
				    selUnsolvedRequirements,
				    selConflictMap,
				    selObsoleteMap );
   }

   if ( (selName->value()).size() > 0 )
   {
       // not only reset
       posInstallMap = selInstallMap.find( selName->value() );
       if ( posInstallMap != selInstallMap.end() )
       {
	   SelInstallSelection *installSelection = &(posInstallMap->second);
	   installSelection->singleSelect = INSTALL_SELECTED;
       }
       else
       {
	   y2warning( "Selection %s not found",
		      (selName->value()).c_str() );
	   ret = false;
       }


       PackageKey packageKey ( selName->value(), "" );

       selSolver->AddPackage( packageKey,
			      selAdditionalPackages,
			      selUnsolvedRequirements,
			      selConflictMap,
			      selObsoleteMap );

       // Evaluate all suggestions
       PackTagLMap packTagLMap = rawPackageInfo->getSelSuggestsDependency();
       PackTagLMap::iterator selPos;

       for ( selPos = packTagLMap.begin();
	     selPos != packTagLMap.end();
	     selPos++ )
       {
	   PackageKey packageKey = selPos->first;
	   if (  packageKey.name() == selName->value() )
	   {
	       TagList tagList = selPos->second;
	       TagList::iterator pos;
	       for ( pos = tagList.begin(); pos != tagList.end(); pos++ )
	       {
		   posInstallMap = selInstallMap.find( *pos );
		   if ( posInstallMap != selInstallMap.end() )
		   {
		       SelInstallSelection *installSelection =
			   &(posInstallMap->second);
		       if ( installSelection->singleSelect == NO )
		       {
			   installSelection->singleSelect = INSTALL_SUGGESTED;
			   (installSelection->suggest)++;

			   PackageKey packageKey ( *pos, "" );

			   selSolver->AddPackage( packageKey,
						  selAdditionalPackages,
						  selUnsolvedRequirements,
						  selConflictMap,
						  selObsoleteMap );
			   y2debug( "suggested selection %s added",
				    (*pos).c_str() );
		       }
		   }
		   else
		   {
		       y2warning( "Selection %s not found",
				  (*pos).c_str() );
		   }
	       }
	   }
       }
   }

   if ( ret->value() )
   {
      y2debug( "selSelectInstall: RETURN TRUE");
   }
   else
   {
      y2debug( "selSelectInstall: RETURN FALSE");
   }

   return ( ret );
}




/*--------------------------------------------------------------------------*
 * Set  packages to install
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::selectInstallList( const YCPList &packageList,
						const YCPBoolean automatic )
{
   YCPBoolean ret ( true );
   PackageInstallMap::iterator posInstallMap;
   PackVersList   packVersList;

   y2debug( "CALLING selectInstall" );


   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   int counter;
   for ( counter = 0; counter < packageList->size(); counter++ )
   {
      if ( packageList->value(counter)->isString() )
      {
	 string packageName = packageList->value(counter)->asString()->value();
	 y2debug( "         PackageName : %s", packageName.c_str());
	 posInstallMap = packageInstallMap.find( packageName );
	 if ( posInstallMap != packageInstallMap.end() )
	 {
	    InstallSelection *installSelection = &(posInstallMap->second);
	    installSelection->action = INSTALL;
	    if ( !(automatic->value()) )
	       installSelection->singleSelect = INSTALL_SELECTED;
	 }
	 else
	 {
	    y2warning( "Package %s not found",
		       packageName.c_str() );
	    ret = false;
	 }

	 bool basePackage;
	 int installationPosition;
	 int cdNr;
	 string instPath;
	 long buildTime;
	 int rpmSize;
	 string version;

	 rawPackageInfo->getRawPackageInstallationInfo(
						 packageName,
						 basePackage,
						 installationPosition,
						 cdNr,
						 instPath,
						 version,
						 buildTime,
						 rpmSize);

	 PackageKey packageKey ( packageName, version );

	 packVersList.push_back ( packageKey );
      }
   }

   // solve dependencies

   solver->AddPackageList( packVersList,
			   additionalPackages,
			   unsolvedRequirements,
			   conflictMap,
			   obsoleteMap );

   if ( ret->value() )
   {
      y2debug( "selectInstall: RETURN TRUE");
   }
   else
   {
      y2debug( "selectInstall: RETURN FALSE");
   }

   return ( ret );
}



/*--------------------------------------------------------------------------*
 * Set a package to update
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::selectUpdate(const YCPString &packageName)
{
   YCPBoolean ret ( true );
   PackageInstallMap::iterator posInstallMap;

   y2debug( "CALLING selectUpdate" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   posInstallMap = packageInstallMap.find( packageName->value() );
   if ( posInstallMap != packageInstallMap.end() )
   {
      InstallSelection *installSelection = &(posInstallMap->second);
      installSelection->action = UPDATE;
      installSelection->singleSelect = UPDATE_SELECTED;
   }
   else
   {
      y2warning( "Package %s not found",
		 (packageName->value()).c_str() );
      ret = false;
   }

   // solve dependencies
    bool basePackage;
   int installationPosition;
   int cdNr;
   string instPath;
   long buildTime;
   int rpmSize;
   string version;

   rawPackageInfo->getRawPackageInstallationInfo(
						 packageName->value(),
						 basePackage,
						 installationPosition,
						 cdNr,
						 instPath,
						 version,
						 buildTime,
						 rpmSize);

   PackageKey packageKey ( packageName->value(), version );

   solver->AddPackage( packageKey,
		       additionalPackages,
		       unsolvedRequirements,
		       conflictMap,
		       obsoleteMap );

   if ( ret->value() )
   {
      y2debug( "selectUpdate: RETURN TRUE");
   }
   else
   {
      y2debug( "selectUpdate: RETURN FALSE");
   }

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Set  packages for update
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::selectUpdateList(const YCPList &packageList)
{
   YCPBoolean ret ( true );
   PackageInstallMap::iterator posInstallMap;
   PackVersList   packVersList;

   y2debug( "CALLING selectUpdate" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   int counter;
   for ( counter = 0; counter < packageList->size(); counter++ )
   {
      if ( packageList->value(counter)->isString() )
      {
	 string packageName = packageList->value(counter)->asString()->value();
	 y2debug( "         PackageName : %s", packageName.c_str());

	 posInstallMap = packageInstallMap.find( packageName );
	 if ( posInstallMap != packageInstallMap.end() )
	 {
	    InstallSelection *installSelection = &(posInstallMap->second);
	    installSelection->action = UPDATE;
	    installSelection->singleSelect = UPDATE_SELECTED;
	 }
	 else
	 {
	    y2warning( "Package %s not found",
		       packageName.c_str() );
	    ret = false;
	 }

	 bool basePackage;
	 int installationPosition;
	 int cdNr;
	 string instPath;
	 long buildTime;
	 int rpmSize;
	 string version;

	 rawPackageInfo->getRawPackageInstallationInfo(
						 packageName,
						 basePackage,
						 installationPosition,
						 cdNr,
						 instPath,
						 version,
						 buildTime,
						 rpmSize);

	 PackageKey packageKey ( packageName, version );
	 packVersList.push_back ( packageKey );
      }
   }

   // solve dependencies

   solver->AddPackageList( packVersList,
			   additionalPackages,
			   unsolvedRequirements,
			   conflictMap,
			   obsoleteMap );

   if ( ret->value() )
   {
      y2debug( "selectUpdate: RETURN TRUE");
   }
   else
   {
      y2debug( "selectUpdate: RETURN FALSE");
   }

   return ( ret );
}



/*--------------------------------------------------------------------------*
 * Reset the installation-set of a packet
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::deselectInstall(const YCPString &packageName)
{
   YCPBoolean ret ( true );
   PackageInstallMap::iterator posInstallMap;

   y2debug( "CALLING deselectInstall" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());
   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   posInstallMap = packageInstallMap.find( packageName->value() );
   if ( posInstallMap != packageInstallMap.end() )
   {
      InstallSelection *installSelection = &(posInstallMap->second);
      installSelection->action = NONE;
      installSelection->singleSelect = INSTALL_DESELECTED;
   }
   else
   {
      y2warning( "Package %s not found",
		 (packageName->value()).c_str() );
      ret = false;
   }

   // solve dependencies
   bool basePackage;
   int installationPosition;
   int cdNr;
   string instPath;
   long buildTime;
   int rpmSize;
   string version;

   rawPackageInfo->getRawPackageInstallationInfo(
						 packageName->value(),
						 basePackage,
						 installationPosition,
						 cdNr,
						 instPath,
						 version,
						 buildTime,
						 rpmSize);

   PackageKey packageKey ( packageName->value(), version );

   solver->DeletePackage( packageKey,
			  additionalPackages,
			  unsolvedRequirements,
			  conflictMap,
			  obsoleteMap );

   if ( ret->value() )
   {
      y2debug( "deselectInstall: RETURN TRUE");
   }
   else
   {
      y2debug( "deselectInstall: RETURN FALSE");
   }

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Reset the installation-set of a selection
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::deselectSelInstall(const YCPString &selName)
{
   YCPBoolean ret ( true );
   SelInstallMap::iterator posInstallMap;

   y2debug( "CALLING deselectSelInstall" );
   y2debug( "         Selection : %s", (selName->value()).c_str());
   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   posInstallMap = selInstallMap.find( selName->value() );
   if ( posInstallMap != selInstallMap.end() )
   {
      SelInstallSelection *installSelection = &(posInstallMap->second);
      installSelection->singleSelect = INSTALL_DESELECTED;
   }
   else
   {
      y2warning( "Selection %s not found",
		 (selName->value()).c_str() );
      ret = false;
   }

   // solve dependencies
   PackageKey packageKey ( selName->value(), "" );

   selSolver->DeletePackage( packageKey,
			     selAdditionalPackages,
			     selUnsolvedRequirements,
			     selConflictMap,
			     selObsoleteMap );

   // Evaluate all suggestions
   PackTagLMap packTagLMap = rawPackageInfo->getSelSuggestsDependency();
   PackTagLMap::iterator selPos;

   for ( selPos = packTagLMap.begin();
	 selPos != packTagLMap.end();
	 selPos++ )
   {
      PackageKey packageKey = selPos->first;
      if ( packageKey.name() == selName->value() )
      {
	 TagList tagList = selPos->second;
	 TagList::iterator pos;
	 for ( pos = tagList.begin(); pos != tagList.end(); pos++ )
	 {
	    posInstallMap = selInstallMap.find( *pos );
	    if ( posInstallMap != selInstallMap.end() )
	    {
	       SelInstallSelection *installSelection = &(posInstallMap->second);
	       if ( installSelection->singleSelect == INSTALL_SUGGESTED)
	       {
		  (installSelection->suggest)--;
		  if ( installSelection->suggest <= 0 )
		  {
		     PackageKey packageKey ( *pos, "" );
		     selSolver->DeletePackage( packageKey,
					    selAdditionalPackages,
					    selUnsolvedRequirements,
					    selConflictMap,
					    selObsoleteMap );
		     installSelection->suggest = 0;
		     installSelection->singleSelect = NO;
		  }
	       }
	    }
	    else
	    {
	       y2warning( "Selection %s not found",
			  (posInstallMap->first).c_str() );
	    }
	 }
      }
   }

   if ( ret->value() )
   {
      y2debug( "deselectSelInstall: RETURN TRUE");
   }
   else
   {
      y2debug( "deselectSelInstall: RETURN FALSE");
   }

   return ( ret );
}



/*--------------------------------------------------------------------------*
 * Reset the update-set of a packet
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::deselectUpdate(const YCPString &packageName)
{
   YCPBoolean ret ( true );
   PackageInstallMap::iterator posInstallMap;

   y2debug( "CALLING deselectUpdate" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());
   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   posInstallMap = packageInstallMap.find( packageName->value() );
   if ( posInstallMap != packageInstallMap.end() )
   {
      InstallSelection *installSelection = &(posInstallMap->second);
      installSelection->action = NONE;
      installSelection->singleSelect = UPDATE_DESELECTED;
   }
   else
   {
      y2warning( "Package %s not found",
		 (packageName->value()).c_str() );
      ret = false;
   }

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Set a packet to delete
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::selectDelete(const YCPString &packageName)
{
   YCPBoolean ret ( true );
   PackageInstallMap::iterator posInstallMap;

   y2debug( "CALLING selectDelete" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   posInstallMap = packageInstallMap.find( packageName->value() );
   if ( posInstallMap != packageInstallMap.end() )
   {
      InstallSelection *installSelection = &(posInstallMap->second);
      installSelection->action = DELETE;
      installSelection->singleSelect = DELETE_SELECTED;
   }
   else
   {
      y2warning( "Package %s not found",
		 (packageName->value()).c_str() );
      ret = false;
   }

   // solve dependencies
   InstPackageMap::iterator posInstalled =
      instPackageMap.find ( packageName->value() );
   if ( posInstalled != instPackageMap.end() )
   {
      InstPackageElement packageElement =
	 posInstalled->second;

      PackageKey packageKey ( packageName->value(),
			      getVersion ( packageName->value(), true ) );

      solver->DeletePackage( packageKey,
			     additionalPackages,
			     unsolvedRequirements,
			     conflictMap,
			     obsoleteMap );
   }
   else
   {
      ret = false;
      y2debug( "selectDelete: Package not found in installed package-list");
   }

   if ( ret->value() )
   {
      y2debug( "selectDelete: RETURN TRUE");
   }
   else
   {
      y2debug( "selectDelete: RETURN FALSE");
   }
   return ( ret );
}

/*--------------------------------------------------------------------------*
 * Reset the delete-set of a packet
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::deselectDelete(const YCPString &packageName)
{
   YCPBoolean ret ( true );
   PackageInstallMap::iterator posInstallMap;

   y2debug( "CALLING deselectDelete" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   posInstallMap = packageInstallMap.find( packageName->value() );
   if ( posInstallMap != packageInstallMap.end() )
   {
      InstallSelection *installSelection = &(posInstallMap->second);
      if ( installSelection->action == DELETE )
      {
	 installSelection->action = NONE;
	 installSelection->singleSelect = DELETE_DESELECTED;
      }

      if ( ( installSelection->isInstalled &&
	     installSelection->action != DELETE ) ||
	   installSelection->action == INSTALL ||
	   installSelection->action == UPDATE )
      {
	 // solve dependencies if the package is installed or
	 // has to be installed
	 InstPackageMap::iterator posInstalled =
	    instPackageMap.find ( packageName->value() );
	 if ( posInstalled != instPackageMap.end() )
	 {
	    InstPackageElement packageElement =
	       posInstalled->second;
	    PackageKey packageKey ( packageName->value(),
				    getVersion (packageName->value(),
						true ) );

	    solver->AddPackage( packageKey,
				additionalPackages,
				unsolvedRequirements,
				conflictMap,
				obsoleteMap );

	 }
	 else
	 {
	    ret = false;
	    y2debug( "selectDelete: Package not found in installed package-list");
	 }
      }
   }
   else
   {
      y2warning( "Package %s not found",
		 (packageName->value()).c_str() );
      ret = false;
   }

   if ( ret->value() )
   {
      y2debug( "deselectDelete: RETURN TRUE");
   }
   else
   {
      y2debug( "deselectDelete: RETURN FALSE");
   }

   return ( ret );
}

/*-------------------------------------------------------------------------*
 * Delete Additional Packages Dependencies where package X needs
 * the tag "tagName".
 * X are all current selected packages
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::deleteAdditionalDependencies(
				const YCPString &tagName)
{
   YCPBoolean ret = true;

   y2debug( "CALLING deleteAdditionalDependencies" );
   y2debug( "         TagName : %s", (tagName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   solver->IgnoreAdditionalPackages( tagName->value() );


   // setting solver
   solver->SolveDependencies( additionalPackages,
			      unsolvedRequirements,
			      conflictMap,
			      obsoleteMap );

   return ( ret );
}

/*-------------------------------------------------------------------------*
 * Delete the UnsolvedRequriements Dependencie
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::deleteUnsolvedRequirements(
						const YCPString &tagName )
{
   YCPBoolean ret = true;

   y2debug( "CALLING deleteUnsolvedRequirements" );
   y2debug( "         tagName : %s", (tagName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   solver->IgnoreUnsolvedRequirements( tagName->value() );

   // setting solver
   solver->SolveDependencies( additionalPackages,
			      unsolvedRequirements,
			      conflictMap,
			      obsoleteMap );

   return ( ret );
}

/*-----------------------------------------------------------------------*
 * Delete the Conflicts Dependencie where package packageName excludes
 * the packages excludePackageName
 *-----------------------------------------------------------------------*/
YCPValue PackageAgent::deleteConflictDependencies(
					const YCPString &packageName1,
					const YCPString &packageName2 )
{
   YCPBoolean ret = true;

   y2debug( "CALLING deleteConflictDependencies" );
   y2debug( "         PackageName : %s", (packageName1->value()).c_str());
   y2debug( "         PackageName : %s", (packageName2->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   solver->IgnoreConflict( packageName1->value(),
			   packageName2->value() );

   // setting solver
   solver->SolveDependencies( additionalPackages,
			      unsolvedRequirements,
			      conflictMap,
			      obsoleteMap );

   return ( ret );
}


/*-------------------------------------------------------------------------*
 * Delete the UnsolvedRequriements of selction Dependencie
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::deleteSelUnsolvedRequirements(
						const YCPString &tagName )
{
   YCPBoolean ret = true;

   y2debug( "CALLING deleteSelUnsolvedRequirements" );
   y2debug( "         tagName : %s", (tagName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   selSolver->IgnoreUnsolvedRequirements( tagName->value() );

   // setting solver
   selSolver->SolveDependencies( selAdditionalPackages,
				 selUnsolvedRequirements,
				 selConflictMap,
				 selObsoleteMap );

   return ( ret );
}

/*-----------------------------------------------------------------------*
 * Delete the Conflicts Dependencie where selection selecName excludes
 * the selection excludeSelName
 *-----------------------------------------------------------------------*/
YCPValue PackageAgent::deleteSelConflictDependencies(
					const YCPString &selectionName1,
					const YCPString &selectionName2 )
{
   YCPBoolean ret = true;

   y2debug( "CALLING deleteSelConflictDependencies" );
   y2debug( "         SelectionName : %s", (selectionName1->value()).c_str());
   y2debug( "         SelectionName : %s", (selectionName2->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return ( YCPBoolean(false) );
   }

   selSolver->IgnoreConflict( selectionName1->value(),
			      selectionName2->value() );

   // setting solver
   selSolver->SolveDependencies( selAdditionalPackages,
				 selUnsolvedRequirements,
				 selConflictMap,
				 selObsoleteMap );

   return ( ret );
}



/*--------------------------------------------------------------------------*
 * Get the long-description of a packet
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getLongDesc(const YCPString &packageName)
{
   YCPString ret("");
   PackageInstallMap::iterator posInstallMap;
   string shortDescription="";
   string longDescription="";
   string notify="";
   string delDescription="";
   string category = "";
   int size = 0;

   y2debug( "CALLING getLongDesc" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return  YCPVoid() ;
   }
   posInstallMap = packageInstallMap.find( packageName->value() );
   if ( posInstallMap != packageInstallMap.end() )
   {
      if ( rawPackageInfo->getRawPackageDescritption( packageName->value(),
						      shortDescription,
						      longDescription,
						      notify,
						      delDescription,
						      category,
						      size) )
      {
	 ret = YCPString( longDescription );
      }
      else
      {
	 y2error( "getRawPackageDescription return ERROR");
      }
   }
   else
   {
      y2warning( "Package %s not found",
		 (packageName->value()).c_str() );
   }

   y2debug( "getLongDesc RETURN %s",
	  (ret->value()).c_str());

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Get package version
 *
 * - overloaded, don't confuse this with getVersion( string, boolean ) !
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getVersion(const YCPString &packageName)
{
   YCPString ret("");
   PackageInstallMap::iterator posInstallMap;

   y2debug( "CALLING getVersion" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return  YCPVoid() ;
   }
   posInstallMap = packageInstallMap.find( packageName->value() );
   if ( posInstallMap != packageInstallMap.end() )
   {
       string version = getVersion( packageName->value(), false );
       ret = YCPString( version );
   }
   else
   {
      y2warning( "Package %s not found",
		 (packageName->value()).c_str() );
   }

   y2debug( "getVersion RETURN %s",
	  (ret->value()).c_str());

   return ( ret );
}

/*--------------------------------------------------------------------------*
 * Get the short-description of a packet
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getShortDesc(const YCPString &packageName)
{
   YCPList ret;
   string label_ti;
   int    size_ii = 0;

   y2debug( "CALLING getShortDesc" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return  YCPVoid() ;
   }

   PkdData cpkg_pCi = rawPackageInfo->getPackageByName( packageName->value() );
   if ( !cpkg_pCi ) {
     y2warning( "Package %s not found", packageName->value().c_str() );
   } else {
     label_ti = cpkg_pCi->label();
     size_ii  = cpkg_pCi->sizeInK();
     ret->add ( YCPString  ( label_ti ) );
     ret->add ( YCPInteger ( size_ii ) );
   }

   y2debug( "getShortDesc RETURN %s : %dK", label_ti.c_str(), size_ii );

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Get the delete-notify of a packet
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getDelDesc(const YCPString &packageName)
{
   YCPString ret("");

   y2debug( "CALLING getDelDesc" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   PkdData cpkg_pCi = rawPackageInfo->getPackageByName( packageName->value() );
   if ( !cpkg_pCi ) {
     y2warning( "Package %s not found", packageName->value().c_str() );
   } else {
     ret = YCPString( cpkg_pCi->delNotify() );
   }


   y2debug( "getDelDesc RETURN %s", ret->value().c_str());

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Get the categories of a packet
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getCategory(const YCPString &packageName)
{
   YCPList ret;

   y2debug( "Who's still using getCategory?" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   // unsused YaST1 stuff
   return YCPList();
}

/*--------------------------------------------------------------------------*
 * Get the Copyright of a packet
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getCopyright(const YCPString &packageName)
{
   if ( rawPackageInfo == NULL ) {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   YCPString ret( "" );
   PkdData cpkg_pCi = rawPackageInfo->getPackageByName( packageName->value() );

   if ( !cpkg_pCi ) {
     y2warning( "Package %s not found", packageName->value().c_str() );
   } else {
     ret = YCPString( cpkg_pCi->copyright() );
   }
   return ret;
}

/*--------------------------------------------------------------------------*
 * Get the Author of a packet
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getAuthor(const YCPString &packageName)
{
   if ( rawPackageInfo == NULL ) {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   YCPString ret( "" );
   PkdData cpkg_pCi = rawPackageInfo->getPackageByName( packageName->value() );

   if ( !cpkg_pCi ) {
     y2warning( "Package %s not found", packageName->value().c_str() );
   } else {
     ret = YCPString( cpkg_pCi->author() );
   }
   return ret;
}

/*--------------------------------------------------------------------------*
 * Get the Size of a packet (in K)
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getSizeInK(const YCPString &packageName)
{
   if ( rawPackageInfo == NULL ) {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   off_t sizeInK_ii = 0;
   PkdData cpkg_pCi = rawPackageInfo->getPackageByName( packageName->value() );

   if ( !cpkg_pCi ) {
     y2warning( "Package %s not found", packageName->value().c_str() );
   } else {
     sizeInK_ii = cpkg_pCi->sizeInK();
   }
   return YCPInteger( sizeInK_ii );
}

/*--------------------------------------------------------------------------*
 * Get the notify-description of a package
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getNotifyDesc(const YCPString &packageName)
{
   YCPString ret("");

   y2debug( "CALLING getNotifyDesc" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   PkdData cpkg_pCi = rawPackageInfo->getPackageByName( packageName->value() );
   if ( !cpkg_pCi ) {
     y2warning( "Package %s not found", packageName->value().c_str() );
   } else {
     ret = YCPString( cpkg_pCi->instNotify() );
   }

   y2debug( "getNotifyDesc RETURN %s",
	  (ret->value()).c_str());

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Get the shortname of a package ( which is used in rpm )
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getShortName(const YCPString &packageName)
{
   YCPString ret("");

   y2debug( "CALLING getShortName" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   ret = YCPString( rawPackageInfo->getShortName( packageName->value() ));

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Get the notify-description of a selection
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getSelNotifyDesc(const YCPString &selName)
{
   YCPString ret("");
   PackList packageList;
   string groupDescription;
   string kind;
   bool visible;
   string requires;
   string conflicts;
   string suggests;
   string provides;
   string version;
   string architecture;
   string longDescription;
   string size;
   string notify;
   string delNotify;

   y2debug( "CALLING getSelNotifyDesc" );
   y2debug( "         selection : %s", (selName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   rawPackageInfo->getSelectionGroupList ( selName->value(),
					   packageList,
					   groupDescription,
					   kind,
					   visible,
					   requires,
					   conflicts,
					   suggests,
					   provides,
					   version,
					   architecture,
					   longDescription,
					   size,
					   notify,
					   delNotify );

   ret = YCPString( notify );

   y2debug( "getSelNotifyDesc RETURN %s",
	  (ret->value()).c_str());

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Get the del-notify-description of a selection
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getSelDelDesc(const YCPString &selName)
{
   YCPString ret("");
   PackList packageList;
   string groupDescription;
   string kind;
   bool visible;
   string requires;
   string conflicts;
   string suggests;
   string provides;
   string version;
   string architecture;
   string longDescription;
   string size;
   string notify;
   string delNotify;

   y2debug( "CALLING getSelDelDesc" );
   y2debug( "         selection : %s", (selName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   rawPackageInfo->getSelectionGroupList ( selName->value(),
					   packageList,
					   groupDescription,
					   kind,
					   visible,
					   requires,
					   conflicts,
					   suggests,
					   provides,
					   version,
					   architecture,
					   longDescription,
					   size,
					   notify,
					   delNotify );

   ret = YCPString( delNotify );

   y2debug( "getSelDelDesc RETURN %s",
	  (ret->value()).c_str());

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Get the status of a package like X,i,d....
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getPackageStatus(const YCPString &packageName)
{
   YCPString ret("");
   PackageInstallMap::iterator posInstallMap;
   string status="";

   y2debug( "CALLING getPackageStatus" );
   y2debug( "         PackageName : %s", (packageName->value()).c_str());

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }
   posInstallMap = packageInstallMap.find( packageName->value() );
   if ( posInstallMap != packageInstallMap.end() )
   {
      InstallSelection installSelection = posInstallMap->second;

      if ( containsPackage ( additionalPackages,
			     (string)posInstallMap->first ) )
      {
	 // automatik
	 status = "a";
      }

      if ( installSelection.isInstalled )
      {
	 status = "i";
      }
      switch ( installSelection.action )
      {
	 case INSTALL:
	    status = "X";
	    break;
	 case DELETE:
	    status = "d";
	    break;
	 case UPDATE:
	    status = "u";
	    break;
	 default:
	    break;
      }
   }
   else
   {
      y2warning( "Package %s not found",
		 (packageName->value()).c_str() );
   }

   ret = YCPString( status );
   y2debug( "getPackageStatus RETURN %s",
	  (ret->value()).c_str());

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Calculates the dependencies and returns a map like:
 * $["REQUIRE":[ $["tag":"tagname1","packages":["pack1","pack2","pack3"]],
 *          $["tag":"tagname2","packages":["pack4","pack5"]]],  ...
 *  ,
 *  "ADD":["pack6","pack8",...],
 *  "CONFLICT": [$["name":"pack9","packages":["pack10","pack11"]],
 *          $["name":"pack12","packages":["pack13"]]],
 *  "OBSOLETE": [ [ pack25, [], pack26, [] ],
 *		     [ pack27, [], pack28, [] ] ]
 *  ]
 * Explanation:
 * $["REQUIRE":[ $["tag":"tagname1","packages":["pack1","pack2","pack3"]],
 *          $["tag":"tagname2","packages":["pack4","pack5"]]],  ...
 *
 * The user have to select ONE packet of every group, e.g. from browser.
 * ( pack1 or pack2 or pack3 ).
 *
 * "ADD":["pack6","pack8",...]:These packets are needed from other packages
 * and are selected automatically by the dependency-check. The user does
 * not select anything.
 *
 * "OBSOLETE":[ [ pack25,<version>,[], pack26,<version>, [] ],
 *		     [ pack27, <version>,[], pack28,<version>,[] ] ]
 *
 * pack25, list with packages which require pack25, obsoletes pack26,
 * list of packages which require pack26
 *
 *--------------------------------------------------------------------------*/
YCPValue	PackageAgent::getDependencies(void)
{
   YCPMap ret;

   y2debug( "CALLING getDependencies" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   // REQUIRE

   y2debug( "getDependencies: REQUIRE-dependencies");

   YCPList requireList;
   TagPackVersLMap::iterator posRequire;
   for ( posRequire = unsolvedRequirements.begin();
	 posRequire != unsolvedRequirements.end();
	 posRequire++ )
   {
      // every tag which have requires dependencies
      YCPMap requireMap;
      YCPList packageList;
      PackVersList packList = posRequire->second;
      PackVersList::iterator posPackVersList;

      y2debug( "getDependencies:   tag: %s",
	     ((string)posRequire->first).c_str());

      for ( posPackVersList = packList.begin();
	    posPackVersList != packList.end();
	    posPackVersList++ )
      {
	 // Each Require dependencies of the tag

	 PackageKey packageKey = *posPackVersList;
         packageList->add ( YCPString(packageKey.name()) );
	 y2debug( "getDependencies:            %s",
		packageKey.name().c_str());
      }

      // construct the map
      requireMap->add ( YCPString ( TAG ), YCPString ( posRequire->first ) );
      requireMap->add ( YCPString ( PACKAGES ), packageList );

      //insert into the Require-list
      requireList->add ( requireMap );
   }

   // ADD

   y2debug( "getDependencies: ADD-dependencies");

   YCPList addList;
   PackVersList::iterator posAdd;
   for ( posAdd = additionalPackages.begin();
	 posAdd != additionalPackages.end();
	 posAdd++ )
   {
      // create ADD List
      PackageKey packageKey = *posAdd;
      addList->add ( YCPString ( packageKey.name() ) );
      y2debug( "getDependencies:            %s",
	     packageKey.name().c_str());
   }

   // CONFLICT

   y2debug( "getDependencies: CONFLICT-dependencies");

   YCPList conflictList;
   PackPackVersLMap::iterator posConflict;
   for ( posConflict = conflictMap.begin();
	 posConflict != conflictMap.end();
	 posConflict++ )
   {
      // every package which have CONFLICT dependencies
      YCPMap conflictMap;
      YCPList packageList;
      PackVersList dependList = posConflict->second;
      PackVersList::iterator posDepend;
      PackageKey package = posConflict->first;
      y2debug( "getDependencies:   package: %s",
	     package.name().c_str());

      for ( posDepend = dependList.begin();
	    posDepend != dependList.end();
	    posDepend++ )
      {
	 // Each Conflict dependencies of the packet
	 PackageKey packageKey = *posDepend;
         packageList->add ( YCPString(packageKey.name()) );
	 y2debug( "getDependencies:            %s",
		packageKey.name().c_str());
      }

      // construct the map
      conflictMap->add ( YCPString ( NAME ), YCPString ( package.name() ) );
      conflictMap->add ( YCPString ( PACKAGES ), packageList );

      //insert into the Conflict-list
      conflictList->add ( conflictMap );
   }


   // OBSOLETE

   y2debug( "getDependencies: OBSOLETE-dependencies");

   YCPList allObsoleteList;
   ObsoleteList::iterator posObsolete;
   for ( posObsolete = obsoleteMap.begin();
	 posObsolete != obsoleteMap.end();
	 posObsolete++ )
   {
      // create OBSOLETE List
      ObsoleteStruct obsolete = *posObsolete;
      PackVersList::iterator pos;
      YCPList packListObsoletes;
      YCPList obsoleteList;

      obsoleteList->add ( YCPString ( obsolete.obsoletes ) );
      obsoleteList->add ( YCPString ( obsolete.obsoletesVersion ) );

      y2debug( "getDependencies:  %s",
	     obsolete.obsoletes.c_str());

      for ( pos = obsolete.obsoletesDepPackages.begin();
	    pos != obsolete.obsoletesDepPackages.end();
	    ++pos )
      {
	 PackageKey packageKey = *pos;
	 packListObsoletes->add ( YCPString ( packageKey.name() ) );
	 y2debug( "getDependencies:            %s",
		packageKey.name().c_str());

      }

      obsoleteList->add ( packListObsoletes );

      obsoleteList->add ( YCPString ( obsolete.isObsoleted ) );
      obsoleteList->add ( YCPString ( obsolete.isObsoletedVersion ) );

      y2debug( "getDependencies:  %s",
	     obsolete.isObsoleted.c_str());

      YCPList packListIsObsoleted;

      for ( pos = obsolete.isObsoletedDepPackages.begin();
	    pos != obsolete.isObsoletedDepPackages.end();
	    ++pos )
      {
	 PackageKey packageKey = *pos;
	 packListIsObsoleted->add ( YCPString ( packageKey.name() ) );

	 y2debug( "getDependencies:            %s",
		packageKey.name().c_str());
      }

      obsoleteList->add ( packListIsObsoleted );

      allObsoleteList->add ( obsoleteList );
   }


   // Create RETURN-map
   ret->add ( YCPString ( REQUIRE ), requireList );
   ret->add ( YCPString ( ADD ), addList );
   ret->add ( YCPString ( CONFLICT ), conflictList );
   ret->add ( YCPString ( OBSOLETE ), allObsoleteList );

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Calculates the dependencies and returns a map like:
 * $["REQUIRE":[ $["tag":"tagname1","selections":["sel1","sel2","sel3"]],
 *          $["tag":"tagname2","selections":["sel4","sel5"]]],  ...
 *  ,
 *  "ADD":["sel6","sel8",...],
 *  "CONFLICT": [$["name":"sel9","selections":["sel10","sel11"]],
 *          $["name":"sel12","selections":["sel13"]]],
 *  ]
 * Explanation:
 *
 * "REQUIRE":[ $["tag":"tagname1","selections":["sel1","sel2","sel3"]],
 *          $["tag":"tagname2","selections":["sel4","sel5"]]],  ...
 * The user have to select ONE selection of every group, e.g. from browser.
 * ( sel1 or sel2 or sel3 ).
 *
 * "ADD":["sel6","sel8",...]:These selections are needed from other selections
 * and are selected automatically by the dependency-check. The user does
 * not select anything.
 *
 *--------------------------------------------------------------------------*/
YCPValue	PackageAgent::getSelDependencies(void)
{
   YCPMap ret;

   y2debug( "CALLING getSelDependencies" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   // REQUIRE

   y2debug( "getSelDependencies: REQUIRE-dependencies");

   YCPList requireList;
   TagPackVersLMap::iterator posRequire;
   for ( posRequire = selUnsolvedRequirements.begin();
	 posRequire != selUnsolvedRequirements.end();
	 posRequire++ )
   {
      // every tag which have requires dependencies
      YCPMap requireMap;
      YCPList selList;
      PackVersList packList = posRequire->second;
      PackVersList::iterator posPackVersList;

      y2debug( "getSelDependencies:   tag: %s",
	     ((string)posRequire->first).c_str());

      for ( posPackVersList = packList.begin();
	    posPackVersList != packList.end();
	    posPackVersList++ )
      {
	 // Each Require dependencies of the tag

	 PackageKey packageKey = *posPackVersList;
         selList->add ( YCPString(packageKey.name()) );
	 y2debug( "getSelDependencies:            %s",
		packageKey.name().c_str());
      }

      // construct the map
      requireMap->add ( YCPString ( TAG ), YCPString ( posRequire->first ) );
      requireMap->add ( YCPString ( SELECTIONS ), selList );

      //insert into the Require-list
      requireList->add ( requireMap );
   }

   // ADD

   y2debug( "getSelDependencies: ADD-dependencies");

   YCPList addList;
   PackVersList::iterator posAdd;
   for ( posAdd = selAdditionalPackages.begin();
	 posAdd != selAdditionalPackages.end();
	 posAdd++ )
   {
      // create ADD List
      PackageKey packageKey = *posAdd;
      addList->add ( YCPString ( packageKey.name() ) );
      y2debug( "getSelDependencies:            %s",
	     packageKey.name().c_str());
   }

   // CONFLICT

   y2debug( "getSelDependencies: CONFLICT-dependencies");

   YCPList conflictList;
   PackPackVersLMap::iterator posConflict;
   for ( posConflict = selConflictMap.begin();
	 posConflict != selConflictMap.end();
	 posConflict++ )
   {
      // every selection which have CONFLICT dependencies
      YCPMap conflictMap;
      YCPList selList;
      PackVersList dependList = posConflict->second;
      PackVersList::iterator posDepend;
      PackageKey selection = posConflict->first;
      y2debug( "getSelDependencies:   selection: %s",
	     selection.name().c_str());

      for ( posDepend = dependList.begin();
	    posDepend != dependList.end();
	    posDepend++ )
      {
	 // Each Conflict dependencies of the packet
	 PackageKey packageKey = *posDepend;
         selList->add ( YCPString(packageKey.name()) );
	 y2debug( "getDependencies:            %s",
	       packageKey.name().c_str());
      }

      // construct the map
      conflictMap->add ( YCPString ( NAME ), YCPString ( selection.name() ) );
      conflictMap->add ( YCPString ( SELECTIONS ), selList );

      //insert into the Conflict-list
      conflictList->add ( conflictMap );
   }

   // Create RETURN-map
   ret->add ( YCPString ( REQUIRE ), requireList );
   ret->add ( YCPString ( ADD ), addList );
   ret->add ( YCPString ( CONFLICT ), conflictList );

   return ( ret );
}

/*--------------------------------------------------------------------------*
 * Simulates the delete of the package "packageName" and returns all
 *  selected packages, that have then unfullfilled dependencies
 *--------------------------------------------------------------------------*/
YCPValue	PackageAgent::getBreakingPackageList(
					const YCPString &packageName)
{
   YCPList ret;

   y2debug( "CALLING getBreakingPackageList" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   bool basePackage;
   int installationPosition;
   int cdNr;
   string instPath;
   long buildTime;
   int rpmSize;
   string version;

   rawPackageInfo->getRawPackageInstallationInfo(
						 packageName->value(),
						 basePackage,
						 installationPosition,
						 cdNr,
						 instPath,
						 version,
						 buildTime,
						 rpmSize);

   PackageKey packageKey ( packageName->value(), version );

   PackVersList packList;
   PackVersList::iterator pos;
   solver->GetBreakingPackageList( packageKey,
				   packList );

   for ( pos = packList.begin();
	 pos != packList.end();
	 pos++ )
   {
      PackageKey packageKey = *pos;
      ret->add ( YCPString(packageKey.name()) );
      y2debug( "getBreakingPackageList:            %s",
	     packageKey.name().c_str());
   }

   return ( ret );
}




/*--------------------------------------------------------------------------*
 * Calculates the required disk space for the current selection.
 * Map a and the return map have the same format:
 *     [$["name":"/","used":0,"free":1500],
 *	  $["name":"var",used:0,"free":100000]]
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getDiskSpace(const YCPList &partitions)
{

   y2debug( "CALLING getDiskSpace" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   YCPList ret;
   PartitionList partitionList;
   PackList packageList;
   PackList deleteList;
   PackagePartitionSizeMap packagePartitionSizeMap;

   partitionList.clear();
   packageList.clear();
   deleteList.clear();
   packagePartitionSizeMap.clear();

   y2debug( "getDiskSpace: to install:" );

   // Create packageList from user selected or deleted packages
   PackageInstallMap::iterator posPackageInstallMap;
   for ( posPackageInstallMap = packageInstallMap.begin();
	 posPackageInstallMap != packageInstallMap.end();
	 ++posPackageInstallMap )
   {
      InstallSelection installSelection = posPackageInstallMap->second;
      if ( installSelection.action == INSTALL &&
	   !installSelection.isInstalled )
      {
	 packageList.insert ( posPackageInstallMap->first );
//	 y2debug( "getDiskSpace:            %s",
//		((string) posPackageInstallMap->first).c_str());
      }
      if ( installSelection.action == DELETE &&
	   installSelection.isInstalled )
      {
	 deleteList.insert ( posPackageInstallMap->first );
//	 y2debug( "getDiskSpace:            %s",
//		((string) posPackageInstallMap->first).c_str());
      }
   }

   y2debug( "getDiskSpace: ADD-dependencies");
   // Packages which has been automatically selected by the solver
   PackVersList::iterator posAdd;
   for ( posAdd = additionalPackages.begin();
	 posAdd != additionalPackages.end();
	 posAdd++ )
   {
      PackageKey packageKey = *posAdd;

      // if it is not user-selected --> insert
      PackList::iterator posPackage = packageList.find ( packageKey.name());

      if ( posPackage == packageList.end() )
      {
	 // not found
	 packageList.insert ( packageKey.name() );
	 y2debug( "getDiskSpace:            %s",
		packageKey.name().c_str());
      }
   }

   if ( installSources )
   {
      // Add list with source-packages
      y2debug( "getDiskSpace: Source-packages");
      PackList sourcePackageList = rawPackageInfo->getSourcePackages();
      PackList::iterator pos;
      for ( pos = sourcePackageList.begin() ; pos != sourcePackageList.end();
	    ++pos )
      {
	 // check, if this package were single-deselected by the user
	 PackageInstallMap::iterator posPackageInstallMap =
	    packageInstallMap.find ( *pos );
	 if ( posPackageInstallMap != packageInstallMap.end() )
	 {
	    InstallSelection installSelection = posPackageInstallMap->second;
	    if ( installSelection.singleSelect != INSTALL_DESELECTED &&
		 installSelection.singleSelect != DELETE_SELECTED )
	    {
	       // check if already exists
	       PackList::iterator posPackage =
		  packageList.find ( (string) *pos);

	       if ( posPackage == packageList.end() )
	       {
		  // not found --> insert
		  packageList.insert ( (string) *pos );
		  y2debug( "getDiskSpace:            %s",
			 ((string)*pos).c_str());
	       }
	    }
	 }
      }
   }

   // Create partitionList
   y2debug( "getDiskSpace: partition-list:" );

   int counter;
   for ( counter = 0; counter < partitions->size(); counter++ )
   {
      if ( partitions->value(counter)->isMap() )
      {
	 YCPMap partition = partitions->value(counter)->asMap();
	 YCPValue partitionValue =partition->value(YCPString(NAME));
	 if ( !partitionValue.isNull() && partitionValue->isString() )
	 {
	    partitionList.insert ( partitionValue->
				   asString()->value());
	    y2debug( "getDiskSpace:               %s",
		   partitionValue->asString()->value().c_str());
	 }
	 else
	 {
	    y2error( "Value of NAME is not a string");
	 }
      }
      else
      {
	 y2error( "getDiskSpace: parameter is not a map" );
      }
   }

   rawPackageInfo->calculateRequiredDiskSpace( partitionList,
					       packageList,
					       deleteList,
					       packagePartitionSizeMap );
   // setting new sizes
   y2debug( "getDiskSpace: calculated sizes:" );

   for ( counter = 0; counter < partitions->size(); counter++ )
   {
      if ( partitions->value(counter)->isMap() )
      {
	 PackagePartitionSizeMap::iterator posPartitionSizeMap;
	 YCPMap partition = partitions->value(counter)->asMap();
	 YCPMap newPartition;
	 YCPValue name = partition->value(YCPString(NAME));
	 YCPValue used = partition->value(YCPString(USED));
	 YCPValue free = partition->value(YCPString(FREE));
	 long long calculateSpace = 0;

	 if ( !name.isNull() && name->isString() &&
	      !used.isNull() && used->isInteger() &&
	      !free.isNull() && free->isInteger() )
	 {
	    posPartitionSizeMap = packagePartitionSizeMap.find (
					name->asString()->value() );
	    if ( posPartitionSizeMap != packagePartitionSizeMap.end() )
	    {
	       calculateSpace = posPartitionSizeMap->second;
	    }
	    else
	    {
	       y2error( "getDiskSpace: Format error NAME,USED,FREE" );
	    }

	    long long newUsed = used->asInteger()->value() +
	       calculateSpace;
	    long long newFree = free->asInteger()->value() -
	       calculateSpace;
	    // Creating one partition-map
	    newPartition->add ( YCPString(NAME),
				name );
	    newPartition->add ( YCPString(USED),
				YCPInteger(newUsed) );
	    newPartition->add ( YCPString(FREE),
				YCPInteger(newFree) );
	    y2debug( "getDiskSpace:                 %s used:%ld free:%ld",
		   name->asString()->value().c_str(), (long int) newUsed,

		  (long int) newFree);
	    //Insert into partition-list
	    ret->add ( newPartition );
	 }
	 else
	 {
	    y2error( "getDiskSpace: Format error NAME,USED,FREE" );
	 }
      }
      else
      {
	 y2error( "getDiskSpace: parameter is not a map" );
      }
   }

   return ( ret );
}

/*--------------------------------------------------------------------------*
 * Returns a map of installation CDs with the needed disk
 * space of installed packages of each CD ( kBytes ).
 * Examle
 *     $[ 243, 1500, 50, 0, 0, 0, 0 ]
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getNeededCDs( )
{

   y2debug( "CALLING getNeededCDs" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   YCPList ret;
   PackList packageList;

   packageList.clear();

   off_t CDs[30];
   for ( unsigned i = 0; i < 30; i++ ) {
      CDs[i] = 0;
   }

   y2debug( "getNeededCDs: to install:" );

   // Create packageList from user selected or installed packages
   PackageInstallMap::iterator posPackageInstallMap;
   for ( posPackageInstallMap = packageInstallMap.begin();
	 posPackageInstallMap != packageInstallMap.end();
	 ++posPackageInstallMap )
   {
      InstallSelection installSelection = posPackageInstallMap->second;
      if ( (installSelection.action == INSTALL
	    && !installSelection.isInstalled)
	   || installSelection.action == UPDATE )
      {
	 packageList.insert ( posPackageInstallMap->first );
	 // y2debug("getNeededCDs: insert %s", posPackageInstallMap->first.c_str() );
      }
   }

   y2debug( "getNeededCDs: Add-dependencies");
   // Packages which has been automatically selected by the solver
   PackVersList::iterator posAdd;
   for ( posAdd = additionalPackages.begin();
	 posAdd != additionalPackages.end();
	 posAdd++ )
   {
      PackageKey packageKey = *posAdd;

      // if it is not user-selected --> insert
      PackList::iterator posPackage = packageList.find ( packageKey.name());

      if ( posPackage == packageList.end() )
      {
	 // not found
	 packageList.insert ( packageKey.name() );
	 // y2debug("getNeededCDs: insert %s", packageKey.name().c_str() );

      }
   }

   if ( installSources )
   {
      // Add list with source-packages
      y2debug( "getDiskSpace: Source-packages");
      PackList sourcePackageList = rawPackageInfo->getSourcePackages();
      PackList::iterator pos;
      for ( pos = sourcePackageList.begin() ; pos != sourcePackageList.end();
	    ++pos )
      {
	 // check, if this package were single-deselected by the user
	 PackageInstallMap::iterator posPackageInstallMap =
	    packageInstallMap.find ( *pos );
	 if ( posPackageInstallMap != packageInstallMap.end() )
	 {
	    InstallSelection installSelection = posPackageInstallMap->second;
	    if ( installSelection.singleSelect != INSTALL_DESELECTED &&
		 installSelection.singleSelect != DELETE_SELECTED )
	    {
	       // check if already exists
	       PackList::iterator posPackage =
		  packageList.find ( (string) *pos);

	       if ( posPackage == packageList.end() )
	       {
		  // not found --> insert
		  packageList.insert ( (string) *pos );
	       }
	    }
	 }
      }
   }

   PackList::iterator posPackage;
   for ( posPackage = packageList.begin();
	 posPackage != packageList.end();
	 posPackage++ )
   {
     PkdData cpkg_pCi = rawPackageInfo->getPackageByName( *posPackage );
     if ( !cpkg_pCi )
       continue;

     unsigned cdNr = cpkg_pCi->onCD();
     off_t    size = cpkg_pCi->sizeInK();

     if ( cdNr < 30 ){
       CDs[cdNr] += size;
     }
   }

   for ( unsigned i = 1; i <= rawPackageInfo->getCDNumbers(); i++ )
   {
      ret->add ( YCPInteger( CDs[i] ) );
   }

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Evaluate all packages of selected "selections"
 * Returns a list of needed packages.
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getSelPackages( void )
{
   YCPList ret;
   PackList packageList;

   y2debug( "CALLING getSelPackages" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   y2debug( "getSelPackages: selections:" );

   SelInstallMap::iterator pos;

   // evaluate all BASE selections which have to be installed
   for ( pos  = selInstallMap.begin();
	 pos != selInstallMap.end();
	 ++pos )
   {
      SelInstallSelection installSelection = pos->second;

      if ( installSelection.kind == "baseconf" &&
	   ( installSelection.singleSelect == INSTALL_SELECTED ||
	     installSelection.singleSelect == INSTALL_SUGGESTED ||
	     containsPackage ( selAdditionalPackages,
			       (string)pos->first ) ) )
      {
	 string groupDescription;
	 string kind;
	 bool visible;
	 string requires;
	 string conflicts;
	 string suggests;
	 string provides;
	 string version;
	 string architecture;
	 string longDescription;
	 string size;
	 string notify;
	 string delNotify;
	 PackList packList;
	 PackList::iterator posList;

	 y2debug( "getSelInstallPackages:          %s (baseconf)",
		((string)pos->first).c_str());

	 rawPackageInfo->getSelectionGroupList ( pos->first,
						 packList,
						 groupDescription,
						 kind,
						 visible,
						 requires,
						 conflicts,
						 suggests,
						 provides,
						 version,
						 architecture,
						 longDescription,
						 size,
						 notify,
						 delNotify );
	 for ( posList = packList.begin();
	       posList != packList.end();
	       posList++ )
	 {
	    string packageName = *posList;
	    string::size_type begin = packageName.find_first_of(":");

	    if ( begin != string::npos )
	    {
	       // replace package found. But currently ther is nothing
	       // to replace
	       packageList.insert ( packageName.substr( begin +1 ) );
	    }
	    else
	    {
	       packageList.insert ( packageName );
	    }
	 }
      }
   }


   // evaluate all NOT BASE selections which have to be installed
   for ( pos  = selInstallMap.begin();
	 pos != selInstallMap.end();
	 ++pos )
   {
      SelInstallSelection installSelection = pos->second;

      if ( installSelection.kind != "baseconf" &&
	   ( installSelection.singleSelect == INSTALL_SELECTED ||
	     installSelection.singleSelect == INSTALL_SUGGESTED ||
	     containsPackage ( selAdditionalPackages,
			       (string)pos->first ) ) )
      {
	 string groupDescription;
	 string kind;
	 bool visible;
	 string requires;
	 string conflicts;
	 string suggests;
	 string provides;
	 string version;
	 string architecture;
	 string longDescription;
	 string size;
	 string notify;
	 string delNotify;
	 PackList packList;
	 PackList::iterator posList;

	 y2debug( "getSelInstallPackages:          %s (!baseconf)",
		((string)pos->first).c_str());

	 rawPackageInfo->getSelectionGroupList ( pos->first,
						 packList,
						 groupDescription,
						 kind,
						 visible,
						 requires,
						 conflicts,
						 suggests,
						 provides,
						 version,
						 architecture,
						 longDescription,
						 size,
						 notify,
						 delNotify );
	 for ( posList = packList.begin();
	       posList != packList.end();
	       posList++ )
	 {
	    string packageName = *posList;

	    string::size_type begin = packageName.find_first_of(":");

	    if ( begin != string::npos )
	    {
	       // package found which have to be replaced
	       y2debug( "replace package %s with %s",
		      (packageName.substr( 0, begin )).c_str(),
		      (packageName.substr( begin+1 )).c_str());

	       packageList.erase ( packageName.substr( 0, begin ) );
	       packageList.insert ( packageName.substr( begin +1 ) );
	    }
	    else
	    {
	       packageList.insert ( packageName );
	    }
	 }
      }
   }

   // creating return value
   PackList::iterator posPack;
   for ( posPack = packageList.begin();
	 posPack != packageList.end();
	 posPack++ )
   {
      ret->add ( YCPString( *posPack ) );
   }

   return ( ret );
}



/*--------------------------------------------------------------------------*
 * Returns the list of selections which have to be installed.
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getSelInstallSet(void)
{
   YCPList ret;

   y2debug( "CALLING getSelInstallSet" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   y2debug( "getSelInstallSet: selections:" );

   SelInstallMap::iterator pos;

   // evaluate all selections which have to be installed
   for ( pos  = selInstallMap.begin();
	 pos != selInstallMap.end();
	 ++pos )
   {
      SelInstallSelection installSelection = pos->second;

      if ( installSelection.singleSelect == INSTALL_SELECTED ||
	   installSelection.singleSelect == INSTALL_SUGGESTED )
      {
	 ret->add ( YCPString ( pos->first ) );
	 y2debug("getSelInstallSet:          %s",
	       ((string)pos->first).c_str());
      }
      else
      {
	 // auto-selection ?
	 if ( containsPackage ( selAdditionalPackages,
				(string)pos->first ) )
	 {
	    ret->add ( YCPString ( pos->first ) );
	    y2debug( "getSelInstallSet:          %s",
		   ((string)pos->first).c_str());
	 }
      }
   }

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Returns the list of packages which have to be installed.
 * If CDNr is 0, all packages will be returned
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getInstallSet( int CDNr )
{
   y2debug( "CALLING getInstallSet with CD %d", CDNr );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   y2debug( "getInstallSet: packages:" );

   PackageInstallMap::iterator pos;
   PackageInstallInfoMap packageInstallInfoMap;
   int maxPosition = 0;
   PackList sourcePackageList;

   if ( installSources )
   {
      sourcePackageList = rawPackageInfo->getSourcePackages();
   }
   else
   {
      sourcePackageList.clear();
   }

   // evaluate all packages which have to be installed
   for ( pos  = packageInstallMap.begin();
	 pos != packageInstallMap.end();
	 ++pos )
   {
      InstallSelection installSelection = pos->second;
      int installationPosition;
      PackList::iterator posSourcePackageList =
	 sourcePackageList.find ( pos->first );

      if ( installSelection.action == INSTALL ||
	   ( installSources &&
	     posSourcePackageList != sourcePackageList.end() &&
	     !installSelection.singleSelect != INSTALL_DESELECTED ))
      {
	 // is a package which have to be installed, or is
	 // a source-package which have to be installed
	 InstallInfo installInfo;
	 string longDescription = "";
	 string notify = "";
	 string delDescription = "";
	 string category = "";
	 int size = 0;
	 int rpmSize = 0;

	 installInfo.packageName = pos->first;

	 y2debug( "getInstallSet:          %s",
		((string)pos->first).c_str());

	 rawPackageInfo->getRawPackageDescritption(
				installInfo.packageName,
				installInfo.shortDescription,
				longDescription,
				notify,
				delDescription,
				category,
				size);

	 string version;
	 long buildtime;

	 rawPackageInfo->getRawPackageInstallationInfo(
				installInfo.packageName,
				installInfo.basePackage,
				installationPosition,
				installInfo.cdNr,
				installInfo.instPath,
				version, buildtime,
				rpmSize);

	 if ( maxPosition < installationPosition )
	    maxPosition = installationPosition;
	 packageInstallInfoMap.insert(pair<const int, InstallInfo>(
						installationPosition,
						installInfo ));
      }
      else
      {
	 // auto-selection ?
	 if ( containsPackage ( additionalPackages,
				(string)pos->first ) )
	 {
	    InstallInfo installInfo;
	    string longDescription = "";
	    string notify = "";
	    string delDescription = "";
	    string category = "";
	    int size = 0;
	    int rpmSize = 0;

	    installInfo.packageName = pos->first;

	    y2debug( "getInstallSet:    ADD   %s",
		   ((string)pos->first).c_str());

	    rawPackageInfo->getRawPackageDescritption(
				 installInfo.packageName,
				 installInfo.shortDescription,
				 longDescription,
				 notify,
				 delDescription,
				 category,
				 size);

	    string version;
	    long buildtime;

	    rawPackageInfo->getRawPackageInstallationInfo(
				installInfo.packageName,
				installInfo.basePackage,
				installationPosition,
				installInfo.cdNr,
				installInfo.instPath,
				version,
				buildtime,
				rpmSize );

	       if ( maxPosition < installationPosition )
		  maxPosition = installationPosition;
	       packageInstallInfoMap.insert(pair<const int, InstallInfo>(
						installationPosition,
						installInfo ));

	 }
      }
   }

   int counter;
   YCPList ret;
   for ( counter = 0; counter <= maxPosition; counter++ )
   {
      // evaluate installation-order and create installation-map
      YCPList list;
      PackageInstallInfoMap::iterator posMap;

      posMap = packageInstallInfoMap.find ( counter );
      if ( posMap != packageInstallInfoMap.end() )
      {
	 // entry found
	 InstallInfo installInfo = posMap->second;
	 if ( CDNr == 0
	      || CDNr == installInfo.cdNr )
	 {
	     list->add ( YCPString ( installInfo.instPath ) );
	     list->add ( YCPString ( installInfo.shortDescription ) );
	     list->add ( YCPInteger ( installInfo.cdNr ) );
	     list->add ( YCPBoolean ( installInfo.basePackage ) );

	     ret->add ( list );
	 }
      }
   }

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Writes a file which contains all selection and deselections.
 * returns true/false
 * Argument : name of the description file
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::savePackageSelections ( const YCPString &filename )
{
   y2debug( "CALLING savePackageSelections" );
   Entries entries;
   Element element;
   YCPBoolean ret ( true );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   y2debug( "savePackageSelections: packages:" );

   PackageInstallMap::iterator pos;
   PackageInstallInfoMap packageInstallInfoMap;
   PackList sourcePackageList;

   if ( installSources )
   {
      sourcePackageList = rawPackageInfo->getSourcePackages();
   }
   else
   {
      sourcePackageList.clear();
   }

   Values valuesAll;
   Values valuesSingle;

   // evaluate all packages which have to be installed
   for ( pos  = packageInstallMap.begin();
	 pos != packageInstallMap.end();
	 ++pos )
   {
      InstallSelection installSelection = pos->second;
      PackList::iterator posSourcePackageList =
	 sourcePackageList.find ( pos->first );

      if ( !installSelection.isInstalled )
      {
	 if ( installSelection.action == INSTALL ||
	      ( installSources &&
		posSourcePackageList != sourcePackageList.end() &&
		!installSelection.singleSelect != INSTALL_DESELECTED ))
	 {
	    // is a package which have to be installed, or is
	    // a source-package which have to be installed
	    y2debug( "          %s",
		   ((string)pos->first).c_str());

	    valuesAll.push_back ( (string)pos->first );
	 }

	 // Checking if the package has bee single selected
	 if ( installSelection.singleSelect == INSTALL_DESELECTED )
	 {
	     valuesSingle.push_back ( (string)pos->first + " " + DESELECTED );
	 }
	 if ( installSelection.singleSelect == INSTALL_SELECTED )
	 {
	     valuesSingle.push_back ( (string)pos->first + " " + SELECTED );
	 }
      } // if !installed
      else
      {
	  // Package is already installed
	  if ( installSelection.singleSelect != DELETE_SELECTED )
	  {
	     valuesSingle.push_back ( (string)pos->first + " " + SELECTED );
	     y2debug( "          %s already installed",
		      ((string)pos->first).c_str());
	     valuesAll.push_back ( (string)pos->first );
	  }
      }
   }

   element.values = valuesAll;
   element.multiLine = true;
   entries.insert(pair<const string, const Element>
		     ( ALLPACKAGES, element ) );

   element.values = valuesSingle;
   element.multiLine = true;
   entries.insert(pair<const string, const Element>
		     ( PACKAGES, element ) );

   y2debug( " selections:" );

   SelInstallMap::iterator posSel;
   Values valuesSelection;

   // evaluate all selections which have to be installed
   for ( posSel  = selInstallMap.begin();
	 posSel != selInstallMap.end();
	 ++posSel )
   {
      SelInstallSelection installSelection = posSel->second;

      if ( installSelection.singleSelect == INSTALL_SELECTED )
      {
	 y2debug("          %s selected",
	       ((string)posSel->first).c_str());
	 valuesSelection.push_back ( (string)posSel->first + " " + SELECTED );
      }
      if ( installSelection.singleSelect == INSTALL_DESELECTED )
      {
	 y2debug("          %s deselected",
	       ((string)posSel->first).c_str());
	 valuesSelection.push_back ( (string)posSel->first + " " + DESELECTED );
      }
   }

   element.values = valuesSelection;
   element.multiLine = true;
   entries.insert(pair<const string, const Element>
		     ( SELECTIONS, element ) );

   Values valueInstallSource;
   if ( installSources )
   {
       valueInstallSource.push_back ( "true" );
   }
   else
   {
       valueInstallSource.push_back ( "false" );
   }
   element.values = valueInstallSource;
   element.multiLine = false;
   entries.insert(pair<const string, const Element>
		     ( SOURCEINSTALL, element ) );

   // Creating directory
   create_directories( filename->value() );

   // save it to file
   ConfigFile packages( filename->value() );
   if (  !packages.writeFile ( entries,
		    "user package selection for YaST2",
				    ':' ) )
   {
       y2error( "Error while writing the file %s",
		(filename->value()).c_str() );
       ret = false;
   }

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Reads a file which contains all selection and deselections
 * and initialize the package agent with this selections.
 * Returns true/false
 * Argument : name of the description file
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::loadPackageSelections ( const YCPString &filename )
{
   y2debug( "CALLING loadPackageSelections from file %s",
	    (filename->value()).c_str() );
   ConfigFile packageList ( filename->value() );
   Entries entries;
   YCPBoolean ret ( true );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   entries.clear();
   Values valuesAll;
   Element allElement;
   allElement.values = valuesAll;
   allElement.multiLine = true;
   Values valuesSelection;
   Element selectionElement;
   selectionElement.values = valuesSelection;
   selectionElement.multiLine = true;
   Values valuesSingle;
   Element singleElement;
   singleElement.values = valuesSingle;
   singleElement.multiLine = true;
   Values valuesSource;
   Element sourceElement;
   sourceElement.values = valuesSource;
   sourceElement.multiLine = false;

   entries.insert(pair<const string, const Element>
		  ( ALLPACKAGES, allElement ) );
   entries.insert(pair<const string, const Element>
		  ( PACKAGES, singleElement ) );
   entries.insert(pair<const string, const Element>
		  ( SELECTIONS, selectionElement ) );
   entries.insert(pair<const string, const Element>
		  ( SOURCEINSTALL, sourceElement ) );

   if ( packageList.readFile ( entries, " :" ) )
   {
       // Reset all selections
       YCPList dummyList;
       setInstallSelection( dummyList, false );
       // deselect source packages
       setSourceInstallation ( YCPBoolean( false ) );

       Entries::iterator pos;
       SelectionGroupMap::iterator selpos;
       SelectionGroupMap	groupMap;

       rawPackageInfo->getSelectionGroupMap( groupMap );

       y2milestone( "Selecting Selection:");

       pos = entries.find ( SELECTIONS );
       if ( pos != entries.end() );
       {
	   Values values = (pos->second).values;
	   Values::iterator posValues;

	   // selection baseconf
	   for ( posValues = values.begin(); posValues != values.end() ;
		 ++posValues )
	   {
	       string description = *posValues;
	       string::size_type 	begin, end;
	       string selectionName = "";
	       string selectionKind = "";

	       begin = description.find_first_not_of ( " \t" );
	       end = description.find_first_of ( " \t" );
	       // line-end ?
	       if ( end == string::npos )
	       {
		   end= description.length();
	       }

	       selectionName.assign( description, begin, end-begin );

	       begin = description.find_first_not_of ( " \t", end );
	       end = description.find_first_of ( " \t", begin );

	       // line-end ?
	       if ( end == string::npos )
	       {
		   end= description.length();
	       }

	       if ( begin != string::npos )
	       {
		   selectionKind.assign( description, begin, end-begin );
	       }

	       selpos = groupMap.find( selectionName );

	       if ( selpos != groupMap.end() )
	       {
		   SelectionGroup selectionGroup = selpos->second;
		   if ( selectionGroup.kind == "baseconf"
			&& selectionKind == SELECTED )
		   {
		       // select to install
		       selectSelInstall( YCPString ( selectionName ),
					 YCPBoolean ( true ) );
		       y2milestone ( "select %s", selectionName.c_str());
		   }
		   if ( selectionGroup.kind == "baseconf"
			&& selectionKind == DESELECTED )
		   {
		       // deselect
		       deselectSelInstall( YCPString ( selectionName ) );
		       y2milestone ( "deselect %s", selectionName.c_str());
		   }
	       }
	   } // selecting baseconf

	   // selection NON baseconf
	   for ( posValues = values.begin(); posValues != values.end() ;
		 ++posValues )
	   {
	       string description = *posValues;
	       string::size_type 	begin, end;
	       string selectionName = "";
	       string selectionKind = "";

	       begin = description.find_first_not_of ( " \t" );
	       end = description.find_first_of ( " \t" );
	       // line-end ?
	       if ( end == string::npos )
	       {
		   end= description.length();
	       }

	       selectionName.assign( description, begin, end-begin );

	       begin = description.find_first_not_of ( " \t", end );
	       end = description.find_first_of ( " \t", begin );

	       // line-end ?
	       if ( end == string::npos )
	       {
		   end= description.length();
	       }

	       if ( begin != string::npos )
	       {
		   selectionKind.assign( description, begin, end-begin );
	       }

	       selpos = groupMap.find( selectionName );

	       if ( selpos != groupMap.end() )
	       {
		   SelectionGroup selectionGroup = selpos->second;
		   if ( selectionGroup.kind != "baseconf"
			&& selectionKind == SELECTED )
		   {
		       // select to install
		       selectSelInstall( YCPString ( selectionName ),
					 YCPBoolean ( false ) );
		       y2milestone ( "select %s", selectionName.c_str());
		   }
		   if ( selectionGroup.kind != "baseconf"
			&& selectionKind == DESELECTED )
		   {
		       // deselect
		       deselectSelInstall( YCPString ( selectionName ) );
		       y2milestone ( "deselect %s", selectionName.c_str());
		   }
	       }
	   } // selecting NON baseconf
       }

       y2milestone( "Selecting sourcepackages");

       pos = entries.find ( SOURCEINSTALL );
       if ( pos != entries.end() );
       {
	   Values values = (pos->second).values;
	   Values::iterator posValues = values.begin();

	   if ( posValues != values.end() )
	   {
	       if ( *posValues == "true" )
	       {
		   // select source packages
		   y2milestone ( "Installing ALL sourcepackages" );
		   setSourceInstallation ( YCPBoolean( true ) );
	       }
	   }
       }

       // Initialize agent with all packagas of the selectiongroups
       YCPValue packages = getSelPackages();
       setInstallSelection( packages->asList(), true );

       y2milestone( "Selecting Packages:");

       pos = entries.find ( PACKAGES );
       if ( pos != entries.end() );
       {
	   Values values = (pos->second).values;
	   Values::iterator posValues;

	   // select or deselect packages
	   for ( posValues = values.begin(); posValues != values.end() ;
		 ++posValues )
	   {
	       string description = *posValues;
	       string::size_type 	begin, end;
	       string selectionName = "";
	       string selectionKind = "";

	       begin = description.find_first_not_of ( " \t" );
	       end = description.find_first_of ( " \t" );
	       // line-end ?
	       if ( end == string::npos )
	       {
		   end= description.length();
	       }

	       selectionName.assign( description, begin, end-begin );

	       begin = description.find_first_not_of ( " \t", end );
	       end = description.find_first_of ( " \t", begin );

	       // line-end ?
	       if ( end == string::npos )
	       {
		   end= description.length();
	       }

	       if ( begin != string::npos )
	       {
		   selectionKind.assign( description, begin, end-begin );
	       }

	       if ( selectionKind == SELECTED )
	       {
		   // select to install
		   selectInstall( YCPString ( selectionName ),
				  YCPBoolean ( false ) );
		   y2milestone ( "select %s", selectionName.c_str());
	       }
	       if ( selectionKind == DESELECTED )
	       {
		   // deselect
		   deselectInstall( YCPString ( selectionName ) );
		   y2milestone ( "deselect %s", selectionName.c_str());
	       }
	   }
       }
   }
   else
   {
       y2error ( "Cannot read file %s",
		 (filename->value()).c_str() );
       ret = false;
   }

   return ret;
}

/*--------------------------------------------------------------------------*
 * Returns the list of packages which have to be updated or installed
 * Format :[[<inst-path>,<shortdescription>,<CDNr>,<basepackage>]...]
 * If CDNr is 0, all packages will be returned
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getUpdateSet( int CDNr )
{
   y2debug( "CALLING getUpdateSet with CD %d", CDNr );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   y2debug( "getUpdateSet: packages:" );

   PackageInstallMap::iterator pos;
   PackageInstallInfoMap packageInstallInfoMap;
   int maxPosition = 0;

   // evaluate all packages which have to be updated
   for ( pos  = packageInstallMap.begin();
	 pos != packageInstallMap.end();
	 ++pos )
   {
      InstallSelection installSelection = pos->second;
      int installationPosition;

      if ( installSelection.action == UPDATE ||
	   installSelection.action == INSTALL )
      {
	 // is a package which have to be updated or installed

	 InstallInfo installInfo;
	 string longDescription = "";
	 string notify = "";
	 string delDescription = "";
	 string category = "";
	 int size = 0;
	 int rpmSize = 0;

	 installInfo.packageName = pos->first;

	 y2debug( "getUpdateSet:          %s",
		((string)pos->first).c_str());

	 rawPackageInfo->getRawPackageDescritption(
			        installInfo.packageName,
				installInfo.shortDescription,
				longDescription,
				notify,
				delDescription,
				category,
				size);
	 string version;
	 long buildtime;

	 rawPackageInfo->getRawPackageInstallationInfo(
				installInfo.packageName,
				installInfo.basePackage,
				installationPosition,
				installInfo.cdNr,
				installInfo.instPath,
				version,
				buildtime,
				rpmSize );

	 if ( maxPosition < installationPosition )
	    maxPosition = installationPosition;
	 packageInstallInfoMap.insert(pair<const int, InstallInfo>(
						installationPosition,
						installInfo ));
      }
      else
      {
	 // auto-selection ?
	 if ( containsPackage ( additionalPackages,
				(string)pos->first ) )
	 {
	    InstallInfo installInfo;
	    string longDescription = "";
	    string notify = "";
	    string delDescription = "";
	    string category = "";
	    int size = 0;
	    int rpmSize = 0;

	    installInfo.packageName = pos->first;

	    y2debug( "getUpdateSet:    ADD   %s",
		   ((string)pos->first).c_str());

	    rawPackageInfo->getRawPackageDescritption(
			         installInfo.packageName,
				 installInfo.shortDescription,
				 longDescription,
				 notify,
				 delDescription,
				 category,
				 size);

	    string version;
	    long buildtime;

	    rawPackageInfo->getRawPackageInstallationInfo(
				installInfo.packageName,
				installInfo.basePackage,
				installationPosition,
				installInfo.cdNr,
				installInfo.instPath,
				version,
				buildtime,
				rpmSize );

	    if ( maxPosition < installationPosition )
	       maxPosition = installationPosition;
	    packageInstallInfoMap.insert(pair<const int, InstallInfo>(
						installationPosition,
						installInfo ));
	 }
      }
   }

   int counter;
   YCPList ret;
   for ( counter = 0; counter <= maxPosition; counter++ )
   {
      // evaluate installation-order and create update-map
      YCPList list;
      PackageInstallInfoMap::iterator posMap;

      posMap = packageInstallInfoMap.find ( counter );
      if ( posMap != packageInstallInfoMap.end() )
      {
	 // entry found
	 InstallInfo installInfo = posMap->second;
	 if ( CDNr == 0
	      || CDNr == installInfo.cdNr )
	 {
	     list->add ( YCPString ( installInfo.instPath ) );
	     list->add ( YCPString ( installInfo.shortDescription ) );
	     list->add ( YCPInteger ( installInfo.cdNr ) );
	     list->add ( YCPBoolean ( installInfo.basePackage ) );

	     ret->add ( list );
	 }
      }
   }

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Returns the list of packages which have to be updated or installed
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getUpdatePackageList( void )
{
   y2debug( "CALLING getUpdatePackageList" );

   YCPList ret;

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   y2debug( "getUpdatePackageList: packages:" );

   PackageInstallMap::iterator pos;

   // evaluate all packages which have to be updated
   for ( pos  = packageInstallMap.begin();
	 pos != packageInstallMap.end();
	 ++pos )
   {
      InstallSelection installSelection = pos->second;

      if ( installSelection.action == UPDATE ||
	   installSelection.action == INSTALL )
      {
	 // is a package which have to be updated or installed
	  ret->add ( YCPString (  pos->first ) );

	  y2debug( "          %s",
		   ((string)pos->first).c_str());
      }
      else
      {
	 // auto-selection ?
	 if ( containsPackage ( additionalPackages,
				(string)pos->first ) )
	 {
	     ret->add ( YCPString (  pos->first ) );

	     y2debug( "    ADD   %s",
		      ((string)pos->first).c_str());
	 }
      }
   }

   return ( ret );
}



/*--------------------------------------------------------------------------*
 * Returns the list of packages which have to be deleted.
 *--------------------------------------------------------------------------*/
YCPValue PackageAgent::getDeleteSet(void)
{
   YCPList ret;

   y2debug( "CALLING getDeleteSet" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   y2debug( "getDeleteSet: packages:" );

   PackageInstallMap::iterator pos;


   for ( pos  = packageInstallMap.begin();
	 pos != packageInstallMap.end();
	 ++pos )
   {
      InstallSelection installSelection = pos->second;
      int installationPosition;

      if ( installSelection.action == DELETE )
      {
	 InstallInfo installInfo;

	 y2debug( "getDeleteSet:          %s",
		((string)pos->first).c_str());

	 installInfo.packageName = pos->first;
	 installInfo.cdNr = 0;
	 installInfo.basePackage = false;
	 installInfo.shortDescription = "";

	 if ( installSelection.foreignPackage )
	 {
	     // not know package --> getting description via rpm
	     YCPPath path = ".targetpkg.info.summary";
	     YCPValue retScr = mainscragent->Read( path,
						    YCPString ( installInfo.packageName ));
	     if ( retScr->isString() )	// success
	     {
		 installInfo.shortDescription = retScr->asString()->value();
	     }
	 }
	 else
	 {
	     // get information from the common.pkd
	     string longDescription = "";
	     string notify = "";
	     string delDescription = "";
	     string category = "";
	     int size = 0;
	     int rpmSize = 0;

	     rawPackageInfo->getRawPackageDescritption(
				installInfo.packageName,
				installInfo.shortDescription,
				longDescription,
				notify,
				delDescription,
				category,
				size);
	     string version;
	     long buildtime;

	     rawPackageInfo->getRawPackageInstallationInfo(
				installInfo.packageName,
				installInfo.basePackage,
				installationPosition,
				installInfo.cdNr,
				installInfo.instPath,
				version,
				buildtime,
				rpmSize );
	 }

	 YCPList list;
	 list->add ( YCPString ( installInfo.packageName ) );
	 list->add ( YCPString ( installInfo.shortDescription ) );
	 list->add ( YCPInteger ( installInfo.cdNr ) );
	 list->add ( YCPBoolean ( installInfo.basePackage ) );

	 ret->add ( list );
      }
   }

   return ( ret );
}

/*------------------------------------------------------------------------*
 * Saving actual state of the server ( included selected		  *
 * packages, dependencies, .... )					  *
 *------------------------------------------------------------------------*/
YCPValue PackageAgent::saveState ( void )
{
   YCPBoolean ret ( true );

   y2debug( "CALLING saveState" );

   // packages

   savePackageInstallMap.clear();
   savePackageInstallMap = packageInstallMap;
   saveInstallSources = installSources;

   // selections

   if ( selSaveSolver != NULL )
   {
      delete ( selSaveSolver );
      selSaveSolver = NULL;
      selSaveAdditionalPackages.clear();
      selSaveUnsolvedRequirements.clear();
      selSaveConflictMap.clear();
      selSaveObsoleteMap.clear();
      selSaveInstallMap.clear();
   }
   selSaveSolver = new Solver( *selSolver );
   selSaveAdditionalPackages = selAdditionalPackages;
   selSaveUnsolvedRequirements = selUnsolvedRequirements;
   selSaveConflictMap = selConflictMap;
   selSaveObsoleteMap = selObsoleteMap;
   selSaveInstallMap = selInstallMap;

   return ( ret );
}

/*------------------------------------------------------------------------*
 * Restore old state, which have been saved with the call "saveState".    *
 *------------------------------------------------------------------------*/
YCPValue PackageAgent::restoreState( void )
{
   YCPBoolean ret ( true );

   y2debug( "CALLING restoreState" );

   // packages

   if ( savePackageInstallMap.size() > 0 )
   {
       packageInstallMap.clear();
       packageInstallMap = savePackageInstallMap;
       installSources = saveInstallSources;

       PackVersList solverList;
       PackageInstallMap::iterator posInstallMap;

       for ( posInstallMap = packageInstallMap.begin();
	     posInstallMap != packageInstallMap.end();
	     posInstallMap++ )
       {
	   InstallSelection *installSelection = &(posInstallMap->second);

	   // insert into solverList, because this package was
	   // selected to install, update or is installed
	   if ( !installSelection->foreignPackage
		&& ( installSelection->isInstalled ||
		     installSelection->action == INSTALL ||
		     installSelection->action == UPDATE ))
	   {
	       string version = getVersion (posInstallMap->first, true);

	       PackageKey packageKey ( posInstallMap->first, version );

	       solverList.push_back ( packageKey );
	   }
       }

       // adding strange packages
       addStrangePackages ( solverList );

       // setting solver

       solver->SolveDependencies( solverList,
				  additionalPackages,
				  unsolvedRequirements,
				  conflictMap,
				  obsoleteMap );
   }

   // selections

   if ( selSaveSolver != NULL )
   {
      if ( selSolver != NULL )
      {
	 delete ( selSolver );
	 selSolver = NULL;
	 selAdditionalPackages.clear();
	 selUnsolvedRequirements.clear();
	 selConflictMap.clear();
	 selObsoleteMap.clear();
	 selInstallMap.clear();
      }
      selSolver = new Solver( *selSaveSolver );

      selAdditionalPackages = selSaveAdditionalPackages;
      selUnsolvedRequirements = selSaveUnsolvedRequirements;
      selConflictMap = selSaveConflictMap;
      selObsoleteMap = selSaveObsoleteMap;
      selInstallMap = selSaveInstallMap;
   }

   return ( ret );
}

/*------------------------------------------------------------------------*
 * Delete old state, which have been saved with the call "saveState".
 *------------------------------------------------------------------------*/
YCPValue PackageAgent::deleteOldState( void )
{
   YCPBoolean ret ( true );

   y2debug( "CALLING deleteOldState" );

   // packages
   savePackageInstallMap.clear();

   // selections

   if ( selSaveSolver != NULL )
   {
      delete ( selSaveSolver );
      selSaveSolver = NULL;
      selSaveAdditionalPackages.clear();
      selSaveUnsolvedRequirements.clear();
      selSaveConflictMap.clear();
      selSaveObsoleteMap.clear();
   }

   return ( ret );
}

/*-------------------------------------------------------------------------*
 * Select or deselect source-installation
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::setSourceInstallation ( YCPBoolean install )
{
   YCPBoolean ret ( true );

   y2debug( "CALLING setSourceInstallation" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");

      return YCPBoolean(false);
   }

   installSources = install->value();

   return ret;
}


/*-------------------------------------------------------------------------*
 * Check, if there was a single selection of packages
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::isSingleSelected( void )
{
   YCPBoolean ret ( false );

   y2debug( "CALLING isSingleSelected" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPBoolean(false);
   }

   PackageInstallMap::iterator pos;
   for ( pos  = packageInstallMap.begin();
	 pos != packageInstallMap.end();
	 ++pos )
   {
      InstallSelection installSelection = pos->second;
      if ( installSelection.singleSelect != NO)
      {
	 y2debug( "isSingleSelected:          %s found",
		((string)pos->first).c_str());

	 ret = YCPBoolean ( true );
      }
   }

   SelInstallMap::iterator posSel;
   for ( posSel = selInstallMap.begin();
	 posSel != selInstallMap.end();
	 posSel++ )
   {
      SelInstallSelection installSelection = posSel->second;
      if ( installSelection.singleSelect != NO &&
	   installSelection.singleSelect != INSTALL_SUGGESTED &&
	   installSelection.kind != "baseconf" )
      {
	 y2debug( "isSingleSelected:          %s found",
		((string)posSel->first).c_str());
	 ret = YCPBoolean ( true );
      }
   }

   return ret;
}


/*-------------------------------------------------------------------------*
 * Check, if there are packages which has been selected for installation
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::isInstallSelected( void )
{
   YCPBoolean ret ( false );

   y2debug( "CALLING isInstallSelected" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPBoolean(false);
   }

   PackageInstallMap::iterator pos;
   PackList sourcePackageList;
   if ( installSources )
   {
      sourcePackageList = rawPackageInfo->getSourcePackages();
   }
   else
   {
      sourcePackageList.clear();
   }

   for ( pos  = packageInstallMap.begin();
	 pos != packageInstallMap.end();
	 ++pos )
   {
      InstallSelection installSelection = pos->second;
      PackList::iterator posSourcePackageList =
	 sourcePackageList.find ( pos->first );

      if ( installSelection.action == INSTALL ||
	   ( installSources &&
	     posSourcePackageList != sourcePackageList.end() &&
	     !installSelection.singleSelect != INSTALL_DESELECTED ))
      {
	 // is a package which have to be installed, or is
	 // a source-package which have to be installed
	 y2debug( "isInstallSelected:          %s found",
		((string)pos->first).c_str());

	 ret = YCPBoolean ( true );
      }
      else
      {
	 // auto-selection ?
	 if ( containsPackage ( additionalPackages,
				(string)pos->first ) )
	 {
	    y2debug( "getInstallSet:    ADD   %s",
		   ((string)pos->first).c_str());
	    y2debug( "isInstallSelected:          %s found",
		   ((string)pos->first).c_str());

	    ret = YCPBoolean ( true );
	 }
      }
   }

   return ret;
}




/*-------------------------------------------------------------------------*
 *  Check, if the system has been booted from CD
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::isCDBooted( void )
{
   YCPBoolean ret ( false );
   string     filename = "/usr/lib/YaST2/.Reh";
   struct stat  dummyStat;

   y2debug( "CALLING isCDBooted" );

   y2debug( "Checking path %s", filename.c_str() );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPBoolean(false);
   }

   if (  stat( filename.c_str(), &dummyStat ) != -1 )
   {
      // DB found
      ret = true;
   }

   return ret;
}


/*-------------------------------------------------------------------------*
 * Let the server known, that he cannot access the common.pkd
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::closeMedium( void )
{
    y2debug( "CALLING closeMedium" );

    if ( rawPackageInfo == NULL )
    {
	y2error( "missing call setEnvironment()");
	return YCPBoolean ( false );
    }

    rawPackageInfo->closeMedium();

    return YCPBoolean ( true );
}


/*-------------------------------------------------------------------------*
 * get description of all *.sel files
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::getSelGroups( )
{
   YCPList ret;
   SelectionGroupMap::iterator pos;
   SelectionGroupMap	groupMap;


   y2debug( "CALLING getSelGroups" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   rawPackageInfo->getSelectionGroupMap( groupMap );

   y2debug( "getSelGroups: GROUPS:" );

   for ( pos = groupMap.begin(); pos != groupMap.end(); ++pos )
   {
      YCPList groupYCPList;
      SelectionGroup selectionGroup = pos->second;
      if ( selectionGroup.visible )
      {
	 groupYCPList->add ( YCPString ( (string)pos->first ) );
	 y2debug( "getSelGroups:      %s",
		((string)pos->first).c_str());
	 y2debug( "description:      %s",
		selectionGroup.description.c_str());
	 y2debug( "category   :      %s",
		selectionGroup.kind.c_str());
	 if ( selectionGroup.visible )
	 {
	    y2debug( "visible    :      yes");
	 }
	 else
	 {
	    y2debug( "visible    :      no");
	 }
	 y2debug( "requires   :      %s",
		selectionGroup.requires.c_str());
	 y2debug( "conflicts  :      %s",
		selectionGroup.conflicts.c_str());
	 y2debug( "suggests   :      %s",
		selectionGroup.suggests.c_str());
	 y2debug( "provides   :      %s",
		selectionGroup.provides.c_str());
	 y2debug( "version    :      %s",
		selectionGroup.version.c_str());
	 y2debug( "architectur:      %s",
		selectionGroup.architecture.c_str());
	 y2debug( "l-descri   :      %s",
		selectionGroup.longDescription.c_str());
	 y2debug( "size       :      %s",
		selectionGroup.size.c_str());
	 y2debug( "notify     :      %s",
		selectionGroup.notify.c_str());
	 y2debug( "delNotify  :      %s",
		selectionGroup.delNotify.c_str());

	 groupYCPList->add ( YCPString ( selectionGroup.description ) );
	 groupYCPList->add ( YCPString ( selectionGroup.kind ) );
	 ret->add ( YCPList ( groupYCPList ) );
      }
      else
      {
	 y2debug( "getSelGroups:      %s NOT SHOWN",
		((string)pos->first).c_str());
      }
   }

   return ( ret );
}


/*-------------------------------------------------------------------------*
 * Returns a map of packages to which the searchmask-string
 * fits:
 * $["aaa_base":["SuSE Linux Verzeichnisstruktur", "X", 378, "1.2.3-1" ],
 *    "aaa_dir",[...],...]
 *
 * Parameter: Map $[ "searchmask":"informix"; "onlyName":true,
 *                   "casesensitive":false ]
 *-------------------------------------------------------------------------*/
YCPValue PackageAgent::searchPackage (  const YCPMap &searchmap )
{
   YCPMap map;
   PackList packageList;
   PackList::iterator pos;
   YCPValue dummyValue = YCPVoid();
   YCPString searchmask("");
   YCPBoolean onlyName( false );
   YCPBoolean casesensitive( false );

   y2debug( "CALLING searchPackage" );

   if ( rawPackageInfo == NULL )
   {
      y2error( "missing call setEnvironment()");
      return YCPVoid();
   }

   dummyValue = searchmap->value(YCPString(SEARCHMASK));
   if ( !dummyValue.isNull() && dummyValue->isString() )
   {
       searchmask  = dummyValue->asString();
   }
   else
   {
       searchmask = YCPString( "" );
   }

   dummyValue = searchmap->value(YCPString(ONLYNAME));
   if ( !dummyValue.isNull() && dummyValue->isBoolean() )
   {
       onlyName = dummyValue->asBoolean();
   }
   else
   {
       onlyName = YCPBoolean( false );
   }

   dummyValue = searchmap->value(YCPString(CASESENSITIVE));
   if ( !dummyValue.isNull() && dummyValue->isBoolean() )
   {
       casesensitive  = dummyValue->asBoolean();
   }
   else
   {
       casesensitive = YCPBoolean( false );
   }

   packageList = rawPackageInfo->getSearchResult ( searchmask->value(),
						   onlyName->value(),
						   casesensitive->value() );

   y2debug( "searchPackage: packages:" );

   for ( pos = packageList.begin(); pos != packageList.end(); ++pos )
   {
      string shortDescription = "";
      string longDescription = "";
      string notify = "";
      string delDescription = "";
      string category = "";
      string status = "";
      int size = 0;
      bool basePackage;
      int installationPosition;
      int cdNr;
      string instPath;
      long buildTime;
      int rpmSize;
      string version;

      YCPList list;

      // return the map of packages
      PackageInstallMap::iterator posPackage;

      rawPackageInfo->getRawPackageDescritption( (string) *pos,
						 shortDescription,
						 longDescription,
						 notify,
						 delDescription,
						 category,
						 size);
      rawPackageInfo->getRawPackageInstallationInfo(
						    (string) *pos,
						    basePackage,
						    installationPosition,
						    cdNr,
						    instPath,
						    version,
						    buildTime,
						    rpmSize);

      posPackage = packageInstallMap.find ( *pos );
      if ( posPackage != packageInstallMap.end() )
      {
	 // entry found
	 InstallSelection installSelection = posPackage->second;

	 if ( containsPackage ( additionalPackages,
				*pos ) )
	 {
	    // automatik
	    status = "a";
	 }

	 if ( installSelection.isInstalled )
	 {
	    status = "i";
	 }
	 switch ( installSelection.action )
	 {
	    case INSTALL:
	       status = "X";
	       break;
	    case DELETE:
	       status = "d";
	       break;
	    case UPDATE:
	       status = "u";
	       break;
	    default:
	       break;
	 }
      }

      list->add ( YCPString ( shortDescription ) );
      list->add ( YCPString ( status ) );
      list->add ( YCPInteger ( size ) );
      list->add ( YCPString ( version ) );

      map->add ( YCPString ( *pos ),list );

      y2debug( ":      %s",
	     (*pos).c_str());
   }

   return ( map );
}



/*-------------------------------------------------------------------------*
 * Check, if the list contains an entry "packagename"
 *-------------------------------------------------------------------------*/
bool PackageAgent::containsPackage ( PackVersList packList,
			  const string packageName )
{
   PackVersList::iterator pos;

   for ( pos = packList.begin();
	 pos != packList.end();
	 ++pos )
   {
      PackageKey packageKey = *pos;

      if ( packageKey.name() == packageName )
      {
	 return true;
      }
   }
   return false;
}

/*-------------------------------------------------------------------------*
 * Evaluate the version of a package
 * rpm: read version vom RPM-DB ( currently not supported )
 *
 * - overloaded, don't confuse this with getVersion( YCPString ) !
 *-------------------------------------------------------------------------*/
string  PackageAgent::getVersion ( string packageName,
					 const bool rpm )
{
   bool basePackage;
   int installationPosition;
   int cdNr;
   string instPath;
   long buildTime;
   int rpmSize;
   string version = "";

   rawPackageInfo->getRawPackageInstallationInfo(
						 packageName,
						 basePackage,
						 installationPosition,
						 cdNr,
						 instPath,
						 version,
						 buildTime,
						 rpmSize);
   return version;
}


/*-------------------------------------------------------------------------*
 * Returns the position of an element
 *-------------------------------------------------------------------------*/
PackVersList::iterator PackageAgent::posPackage ( PackVersList packList,
						  const string packageName )
{
   PackVersList::iterator pos;

   for ( pos = packList.begin();
	 pos != packList.end();
	 ++pos )
   {
      PackageKey packageKey = *pos;

      if ( packageKey.name() == packageName )
      {
	 return pos;
      }
   }
   return packList.end();
}

/*-------------------------------------------------------------------------*
 * Add strange packages to a list which are no longer
 * in the common.pkd
 *------------------------------------------------------------------------*/
void PackageAgent::addStrangePackages ( PackVersList &packageList )
{
    // evaluate all packages which are on the system but no longer
    // in the common.pkd
    InstPackageMap::iterator posPackage;

    for ( posPackage = instPackageMap.begin();
	  posPackage != instPackageMap.end();
	  posPackage++ )
    {
	PackageInstallMap::iterator pos = packageInstallMap.find
	    ( posPackage->first );
	bool isStrange = false;
	if ( pos == packageInstallMap.end() )
	{
	    isStrange = true;
	}
	else
	{
	    InstallSelection *installSelection = &(pos->second);
	    if ( installSelection->foreignPackage )
	    {
		isStrange = true;
	    }
	}
	if ( isStrange )
	{
	    // no longer in the common.pkd
	    InstPackageElement packageElement = posPackage->second;
	    PackageKey packageKey ( posPackage->first,
				    packageElement.version );
	    packageList.push_back ( packageKey );
	}
    }
}

/*-------------------------------------------------------------------------*
 * Reading installed packages via targetpkg agent
 *-------------------------------------------------------------------------*/
void PackageAgent::readInstalledPackages ( InstPackageMap  &instPackageMap )
{
    instPackageMap.clear();

    if ( mainscragent )
    {
	YCPPath path = ".targetpkg.info";
	YCPValue ret = mainscragent->Read( path );

	if ( ret->isMap() )	// success
	{
	    YCPMap variables = ret->asMap();

	    for (YCPMapIterator pos = variables->begin(); pos != variables->end(); ++pos)
	    {
		YCPValue key   = pos.key();
		YCPValue value = pos.value();
		if ( key->isString()
		     && value->isList() )
		{
		    string packagename = key->asString()->value();
		    YCPList packList = value->asList();
		    InstPackageElement package;

		    package.packageName = packagename;
		    if ( packList->size() > 0 )
		    {
			YCPValue val = packList->value(0);
			if ( val->isString() )
			{
			    package.version = val->asString()->value();
			}
		    }
		    if ( packList->size() > 1 )
		    {
			YCPValue val = packList->value(1);
			if ( val->isInteger() )
			{
			    package.buildtime = val->asInteger()->value();
			}
		    }
		    if ( packList->size() > 2 )
		    {
			YCPValue val = packList->value(2);
			if ( val->isInteger() )
			{
			    package.installtime = val->asInteger()->value();
			}
		    }
		    instPackageMap.insert(pair<const string,
					  const InstPackageElement >
					  ( package.packageName, package ) );
		}
	    }
	}
	else
	{
	    y2error( "<.targetpkg.info> System agent returned nil.");
	}
    }
    else
    {
	y2error( "mainscragent not initialized");
    }
}

/*--------------------------- EOF -------------------------------------------*/
