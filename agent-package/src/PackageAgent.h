// -*- c++ -*-

#ifndef PackageAgent_h
#define PackageAgent_h

#include <scr/SCRAgent.h>
#include <scr/SCRInterpreter.h>
#include <Y2.h>
#include <pkg/RawPackageInfo.h>
#include <pkg/Solver.h>

// Execute calls
#define SETENVIRONMENT "setEnvironment"
#define SETINSTALLSELECTION "setInstallSelection"
#define SETDELETESELECTION "setDeleteSelection"
#define SETUPDATESELECTION "setUpdateSelection"
#define SELECTINSTALL "selectInstall"
#define SELECTSELINSTALL "selectSelInstall"
#define SELECTINSTALLLIST "selectInstallList"
#define DESELECTINSTALL "deselectInstall"
#define DESELECTSELINSTALL "deselectSelInstall"
#define SELECTUPDATE "selectUpdate"
#define SELECTUPDATELIST "selectUpdateList"
#define DESELECTUPDATE "deselectUpdate"
#define SELECTDELETE "selectDelete"
#define DESELECTDELETE "deselectDelete"
#define DELETEADDITIONALDEPENDENCIES "deleteAdditionalDependencies"
#define DELETEUNSOLVEDREQUIREMENTS "deleteUnsolvedRequirements"
#define DELETECONFLICTDEPENDENCIES "deleteConflictDependencies"
#define DELETESELUNSOLVEDREQUIREMENTS "deleteSelUnsolvedRequirements"
#define DELETESELCONFLICTDEPENDENCIES "deleteSelConflictDependencies"
#define SAVESTATE "saveState"
#define RESTORESTATE "restoreState"
#define DELETEOLDSTATE "deleteOldState"
#define SETSOURCEINSTALLATION "setSourceInstallation"
#define CHECKBROKENUPDATE "checkBrokenUpdate"
#define SAVEUPDATESTATUS "saveUpdateStatus"
#define BACKUPUPDATESTATUS "backupUpdateStatus"
#define CHECKPACKAGE "checkPackage"
#define CLOSEUPDATE "closeUpdate"
#define SEARCHPACKAGE "searchPackage"
#define COMPARESUSEVERSIONS "compareSuSEVersions"
#define CLOSEMEDIUM "closeMedium"

//Read calls
#define GETPACKAGELIST "packageList"
#define GETHIERARCHYINFORMATION "hierarchyInformation"
#define GETLONGDESC "longDesc"
#define GETSHORTDESC "shortDesc"
#define GETVERSION "version"
#define GETDELDESC "delDesc"
#define GETSELDELDESC "selDelDesc"
#define GETCATEGORY  "category"
#define GETCOPYRIGHT "copyright"
#define GETAUTHOR    "author"
#define GETSIZEINK   "sizeInK"
#define GETNOTIFYDESC "notifyDesc"
#define GETSELNOTIFYDESC "selNotifyDesc"
#define GETDEPENDENCIES "dependencies"
#define GETBREAKINGPACKAGELIST "breakingPackageList"
#define GETSELDEPENDENCIES "selDependencies"
#define GETUPDATELIST "updateList"
#define READVERSIONS "versions"
#define GETDISKSPACE "diskSpace"
#define GETNEEDECDS "neededCDs"
#define GETINSTALLSET "installSet"
#define GETINSTALLSETCD "installSetCD"
#define GETSELINSTALLSET "selInstallSet"
#define GETUPDATESET "updateSet"
#define GETUPDATESETCD "updateSetCD"
#define GETUPDATEPACKAGENAMES "updatePackageNames"
#define GETDELETESET "deleteSet"
#define ISSINGLESELECTED "isSingleSelected"
#define ISINSTALLSELECTED "isInstallSelected"
#define GETSELPACKAGES "selPackages"
#define GETSELGROUPS "selGroups"
#define ISCDBOOTED "isCDBooted"
#define GETPACKAGEVERSION "packageVersion"
#define GETCHANGEDPACKAGENAME "changedPackageName"
#define GETINSTALLSPLITTEDPACKAGES "installSplittedPackages"
#define GETKERNELLIST "kernelList"
#define GETPACKAGESTATUS "packageStatus"
#define PACKAGESELECTIONS "packageSelections" // Write call too
#define GETSHORTNAME "shortName"

//Write calls
#define BRANCH "branch"
#define RPMGROUP "rpmgroup"
#define SEARCHMASK "searchmask"
#define ONLYNAME "onlyName"
#define CASESENSITIVE "casesensitive"
#define TODELETE "Todelete"
#define TOINSTALL "Toinstall"
#define UPDATEMODE "update"
#define ROOTPATH "rootpath"
#define FORCEINIT "forceInit"
#define YASTPATH "yastpath"
#define PACKAGEINFOPATH "packageinfopath"
#define MEMOPTIMIZED "memoptimized"
#define LANGUAGE "language"
#define DUDIR "dudir"
#define PARTITION "partition"
#define NAME "name"
#define TAG "tag"
#define USED "used"
#define FREE "free"
#define COMMONPKD "common.pkd"
#define SERIE "serie"
#define DESCRIPTION "description"
#define PACKAGES "packages"
#define MEDIAINFO "MediaInfo"
#define FILESYSTEMS "Filesystems"
#define REQUIRE "REQUIRE"
#define ADD "ADD"
#define CONFLICT "CONFLICT"
#define OBSOLETE "OBSOLETE"
#define ALLPACKAGES "allPackages"
#define SELECTIONS "selections"
#define PACKAGES "packages"
#define SOURCEINSTALL "sourceInstall"
#define SELECTED "selected"
#define DESELECTED "deselected"

/**
 * @short SCR Agent for package handling
 */

typedef   struct  INSTPACKAGEELEMENT{
      string packageName;	// without extention .rpm ..
      long   buildtime;
      long   installtime;
      string version;
}InstPackageElement;
typedef map<string,InstPackageElement> InstPackageMap;

typedef enum _CompareVersion {
      V_OLDER,
      V_EQUAL,
      V_NEWER,
      V_UNCOMP
} CompareVersion;


class PackageAgent : public SCRAgent
{
public:
    PackageAgent();
    ~PackageAgent();

    /**
     * Reads data. Destroy the result after use.
     * @param path Specifies what part of the subtree should
     * be read. The path is specified _relatively_ to Root()!
     */
    YCPValue Read(const YCPPath& path, const YCPValue& arg = YCPNull());

    YCPValue Execute (const YCPPath& path,
		      const YCPValue& value = YCPNull(),
		      const YCPValue& arg = YCPNull());

    /**
     * Writes data.
     */
    YCPValue Write(const YCPPath& path, const YCPValue& value,
		   const YCPValue& arg = YCPNull());

    /**
     * Get a list of all subtrees.
     */
    YCPValue Dir(const YCPPath& path);

protected:

   /**
    * Initialize the server with the environment delivered by the setMap:
    * $[ "update":true,
    *	"packetinfopath":"/mnt/suse/setup/desc",
    *   "language":"german",
    *   "common.pkd":"common.pkd",
    *   "dudir":"/mnt/suse/setup/du/du.dir",
    *   "partition":[$["name":"/","used":0,"free":1500],
    *	  	     $["name":"var","used":0,"free":100000]],
    *	"rootpath":"/",
    *   "yastpath":"/var/lib/YaST",
    *   "memoptimized":true ]
    **/
   YCPValue	setEnvironment ( YCPMap setMap );


   /**
    * Reads all packet-informations which are described in common.pkd.
    * Returns a map like
    * $["aaa_base":["SuSE Linux Verzeichnisstruktur", "X", 378,<version> ],
    *    "aaa_dir",[...],...]
    **/
   YCPValue	getPackageList( void );

   /**
    * Evaluate a branch of the package-tree.
    * Parameter : $["branch":<branch>, "rpmgroup":true]
    * If branch is NULL the contents of map are the series.
    * If branch is the Name of a serie, the return value is a
    * list of all packages which belongs to the serie.
    * If rpmgroup is true rpmgroups are handled instead of series.
    **/
    YCPValue	getHierarchyInformation(const YCPMap &branchMap );

   /**
    * Set the list of packets which have to be installed.
    * a is the list of packages which have to be installed. Every other
    * install-set is deleted, if notResetSingleSelected == false.
    **/
   YCPValue 	setInstallSelection(const YCPList &packageList,
				     bool notResetSingleSelected );

   /**
    * Set the list of packets which have to be deleted.
    * a is the list of packages which have to be removed. Every other
    * remove-set is deleted.
    **/
   YCPValue	setDeleteSelection(const YCPList &packageList);

   /**
    * Set the list of packets which have to be updated
    * a is the list of packages which have to be updated. Every other
    * update-set is deleted.
    **/
   YCPValue	setUpdateSelection(const YCPList &packageList);

   /**
    * Set a package to install
    **/
   YCPValue	selectInstall(const YCPString &packageName,
			      const YCPBoolean automatic );

   /**
    * Set a selection to install
    **/
   YCPValue	selectSelInstall(const YCPString &selName,
				 const YCPBoolean reset );

   /**
    * Set packages to install
    **/
   YCPValue	selectInstallList(const YCPList &packageList,
				  const YCPBoolean automatic );

   /**
    * Reset the installation-set of a packet
    **/
   YCPValue	deselectInstall(const YCPString &packageName);

   /**
    * Reset the installation-set of a selection
    **/
   YCPValue	deselectSelInstall(const YCPString &selName);

   /**
    * Set a packet to delete
    **/
   YCPValue	selectDelete(const YCPString &packageName);

   /**
    * Reset the delete-set of a packet
    **/
   YCPValue	deselectDelete(const YCPString &packageName);

   /**
    * Set a packet to update
    **/
   YCPValue	selectUpdate(const YCPString &packageName);

   /**
    * Set a packages to update
    **/
   YCPValue	selectUpdateList(const YCPList &packageList);

   /**
    * Reset the update-set of a packet
    **/
   YCPValue	deselectUpdate(const YCPString &packageName);

   /**
   * Delete all Dependencies where package X requires
   * package "packageName".
   * X are all packages
   */
   YCPValue	deleteAdditionalDependencies(const YCPString &packageName);

   /**
   * Delete all Conflict Dependencies between "packageName1" and
   * package "packageName2".
   * "packageName1" is the current selected packages
   */
   YCPValue	deleteConflictDependencies(const YCPString &packageName1,
					   const YCPString &packageName2 );

   /**
   * Delete the unresolved requirements where a package needs
   * one of the packages from tagName
   */
   YCPValue	deleteUnsolvedRequirements( const YCPString &tagName );

   /**
   * Delete all Conflict Dependencies between "selectionName1" and
   * selection "selectionName2".
   * "selectionName1" is the current selected selection
   */
   YCPValue	deleteSelConflictDependencies(const YCPString &selectionName1,
					      const YCPString &selectionName2 );

   /**
   * Delete the unresolved requirements where selection selectionName needs
   * one of the selections from tagName
   */
   YCPValue	deleteSelUnsolvedRequirements( const YCPString &tagName );

   /**
    * Get the long-description of a packet
    **/
   YCPValue	getLongDesc(const YCPString &packageName);

   /**
    * Get the short-description of a packet
    **/
   YCPValue	getShortDesc(const YCPString &packageName);

   /**
    * Get the version of a package
    **/
   YCPValue     getVersion(const YCPString &packageName);

   /**
    * Get the delete-notify of a packet
    **/
   YCPValue	getDelDesc(const YCPString &packageName);

   /**
    * Get the delete-notify of a selection
    **/
   YCPValue	getSelDelDesc(const YCPString &selName);

   /**
    * Get the category-notify of a packet
    **/
   YCPValue	getCategory(const YCPString &packageName);

   /**
    * Get the Copyright of a packet
    **/
   YCPValue	getCopyright(const YCPString &packageName);

   /**
    * Get the Author of a packet
    **/
   YCPValue	getAuthor(const YCPString &packageName);

   /**
    * Get the Size of a packet (in K)
    **/
   YCPValue	getSizeInK(const YCPString &packageName);

   /**
    * Get the notify-description of a package
    **/
   YCPValue	getNotifyDesc(const YCPString &packageName);

   /**
    * Get the shortname of a package ( which is used in rpm )
    **/
   YCPValue	getShortName(const YCPString &packageName);

   /**
    * Get the notify-description of a selection
    **/
   YCPValue	getSelNotifyDesc(const YCPString &selName);

   /**
    * Simulates the delete of the package "packageName" and returns all
    * selected packages, that have then unfullfilled dependencies
    **/
   YCPValue	getBreakingPackageList(const YCPString &packageName);

   /**
    * Get the status of a package like i,d,X....
    **/
   YCPValue	getPackageStatus(const YCPString &packageName);

   /**
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
    * "OBSOLETE":[ [ pack25,<version>, [], pack26,<version>, [] ],
    *		     [ pack27,<version>, [], pack28, <version>,[] ] ]
    *
    * pack25, list with packages which require pack25, obsoletes pack26,
    * list of packages which require pack26
    *
    **/
   YCPValue	getDependencies(void);

   /**
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
    **/
   YCPValue	getSelDependencies(void);

   /**
    * Calculates the required disk space for the current selection.
    * List a and the return list have the same format:
    *     [$["name":"/","used":0,"free":1500],
    *	  $["name":"var",used:0,"free":100000]]
    **/
   YCPValue	getDiskSpace(const YCPList &partitions);

   /**
    * Returns a map of installation CDs with the needed disk
    * space of packages of each CD which have to be installed( KByte ).
    * Example
    *     $[243,1500,50,0,0,0,0,0 ]
    **/
   YCPValue	getNeededCDs( );

   /**
    * Returns the list of packages which have to be installed.
    * If CDNr is 0, all packages will be returned
    **/
   YCPValue	getInstallSet( int CDNr );

   /**
    * Returns the list of selection which have to be installed.
    **/
   YCPValue	getSelInstallSet(void);

   /**
    * Returns the list of packages which have to be updated.
    * Format :[[<inst-path>,<shortdescription>,<CDNr>,<basepackage>]...]
    * If CDNr is 0, all packages will be returned
    **/
   YCPValue	getUpdateSet( int CDNr );

   /**
    * Returns the list of packages which have to be updated.
    **/
   YCPValue	getUpdatePackageList( void );

   /** Evaluate the installed and CD-version of the distri and returns
    *  a map like:
    * $[ "installedVersion":"SuSE 6.3",
    *  "updateVersion":"SuSE 6.4" ]
    *  The udateVersion can only be read, if the CD1 has been mounted !!!!
    **/
   YCPValue	readVersions(void);

   /**
    * Returns the list of packages which have to be deleted.
    **/
   YCPValue	getDeleteSet(void);

   /**
    * Saving actual state of the server ( included selected
    * packages, dependencies, .... )
    */
   YCPValue	saveState ( void );

   /**
    * Restore old state, which have been saved with the call "saveState".
    */
   YCPValue	restoreState ( void );

   /**
    * Delete old state, which have been saved with the call "saveState".
    */
   YCPValue	deleteOldState ( void );

   /**
    * Check, if there was a single selection of packages
    */
   YCPValue	isSingleSelected ( void );

   /**
    * Check, if there are packages which has been selected for installation
    */
   YCPValue	isInstallSelected ( void );

   /**
    * Select or deselect source-installation
    */
   YCPValue	setSourceInstallation ( YCPBoolean install );

   /**
   * get description of all *.sel files
   */
   YCPValue 	getSelGroups( );

   /**
    * Evaluate all packages of selected "selections"
    * Returns a list of needed packages.
    */
   YCPValue 	getSelPackages( void );

   /*
    * Check, if an update has not been successfully
    * Returns a list of packages which have to be installed or delete success
    * fully:
    * $["aaa_base","u", "at", "d", ......]
    */
   YCPValue checkBrokenUpdate( );

   /**
    * Check, if the system has been booted from CD
    */
   YCPValue	isCDBooted ( void );

   /**
    * Calculates the packages which have to be updated  and returns a map like:
    * $["updateBase": TRUE ,
    *  "installedVersion":"SuSE 6.3",
    *  "updateVersion":"SuSE 6.4",
    *  "packages":$["aaa_base":"u", "xfree":"m", "xyz":"m",..] ]
    *  Flag "m" means that the user has to decide updating the package.
    **/
   YCPValue	getUpdateList(void);

   /**
    * Compare the version of installed system with the version of
    * install-medium. Retunrn $["installedGreater": TRUE ,
    *  "installedVersion":"6.3",
    *  "updateVersion":"6.4.0"] if no equal; else $[]
    **/
   YCPValue compareSuSEVersions(const YCPString &to_install_version);

   /**
    * Let the server known, that he cannot access the common.pkd
    **/
   YCPValue closeMedium ( );

   /**
    * Returns a map of kernels which can be installed.
    * Argument: none
    * Format: $[ <kernel-name1>:<description1>, <kernel-name2>:
    *           <description2> ]
    **/
    YCPValue getKernelList ( );

   /**
    * Returns a map of packages to which the searchmask-string
    * fits:
    * $["aaa_base":["SuSE Linux Verzeichnisstruktur", "X", 378, "1.2.3-1" ],
    *    "aaa_dir",[...],...]
    *
    * Parameter: Map $[ "searchmask":"informix"; "onlyName":true,
    *                   "casesensitive":false ]
    **/
    YCPValue searchPackage ( const YCPMap &searchmap );

   /**
    * Save the update-status into /var/lib/YaST/install.lst
    * Input :$["ToDelete":"xyz1","aasdf",....],
    *          "ToInstall":["kaakl","aas"],
    *          "RMode":"Recover" ]
    * Return: ok
    **/
    YCPValue	saveUpdateStatus ( const YCPMap &packageMap );

   /**
    * Save the update-status from /var/lib/YaST/install.lst
    * to /var/lib/YaST/install.lst.bak
    **/
   YCPValue     backupUpdateStatus ( void );


   /**
    * Check, if the package has been installed without errors.
    * Input : package-name
    * Return: list; format:[<rpm-version>,<common.pkd-version>,<rpm-buildtime>,
    *                       <common.pkd-buildtime>]
    **/
   YCPValue	checkPackage ( const YCPString &packageName );

   /**
    * Evaluate the buildtime and version of a package
    * Input : package-name
    * Return: list; format:[<rpm-version>,<common.pkd-version>,<rpm-buildtime>,
    *                       <common.pkd-buildtime>]
    **/
    YCPValue	getPackageVersion ( const YCPString &packageName );

   /**
    * Returns the list of packages, which replace old packages.
    * This packages have to be installed.
    **/
   YCPValue	getChangedPackageName ( void );

   /**
    * Reads a file which contains all selection and deselections
    * and initialize the package agent with this selections.
    * Returns true/false
    * Argument : name of the description file
    **/
   YCPValue	loadPackageSelections ( const YCPString &filename );


   /**
    * Writes a file which contains all selection and deselections.
    * returns true/false
    * Argument : name of the description file
    **/
   YCPValue	savePackageSelections ( const YCPString &filename );

   /**
    * Returns the list of packages, which have to be installed, cause
    * packages have been splitted.
    * Format [ [<splitted package1>, <package to have install1>],
    *	       [<splitted package2>, <package to have install2>], .... ]
    **/
   YCPValue	getInstallSplittedPackages ( void );

   /**
   * Close Update and save  /var/lib/YaST/update.inf if it was successfully
   * Input : basesystem has been updated
   * Return: ok
   **/
   YCPValue closeUpdate ( const YCPBoolean
			  &basesystemUpdated );

   /**
    * compare two versions of a package
    **/
   CompareVersion CompVersion( string left,
			       string right );

   /**
    * Check, if the list contains an entry "packagename"
    **/
   bool containsPackage ( PackVersList packList,
			  const string packageName );

   /**
    * Evaluate the version of a package;
    * rpm: read version vom RPM-DB ( currently not supported )
    **/
   string getVersion ( string packageName,
		       const bool rpm );

    /**
     * Add strange packages to a list which are no longer
     * in the common.pkd
     **/
    void addStrangePackages ( PackVersList &packageList );

    /**
     * Reading installed packages via targetpkg agent
     **/
    void readInstalledPackages ( InstPackageMap  &instPackageMap );

   /**
    * Returns the position of an element
    **/
   PackVersList::iterator posPackage ( PackVersList packList,
				   const string packageName );

   enum Action { NONE, DELETE, INSTALL, UPDATE };
   enum SingleSelect { NO,
		       INSTALL_SELECTED, INSTALL_DESELECTED,
		       DELETE_SELECTED, DELETE_DESELECTED,
		       UPDATE_SELECTED, UPDATE_DESELECTED,
                       INSTALL_SUGGESTED };

   typedef struct INSTALL_SELECTION
   {
      bool isInstalled;
      Action action;
      SingleSelect singleSelect;
      bool foreignPackage;
   } InstallSelection;

   typedef struct SEL_INSTALL_SELECTION
   {
      bool visible;
      string kind;
      SingleSelect singleSelect;
      int suggest;
   } SelInstallSelection;

   typedef map<string,InstallSelection> PackageInstallMap;
   typedef map<string,SelInstallSelection> SelInstallMap;

   typedef struct INSTALL_INFO
   {
      string packageName;
      string instPath;
      string shortDescription;
      int cdNr;
      bool basePackage;
   } InstallInfo;

   typedef map<int,InstallInfo> PackageInstallInfoMap;

   typedef struct SIZE_INFO
   {
      int free;
      int used;
   } SizeInfo;


   typedef map<string,SizeInfo> PartitionSizeMap;

   // Package stuff
   RawPackageInfo 	*rawPackageInfo; // common Info about the packages
   Solver	  	*solver; // solving dependencies
   PackVersList   	additionalPackages;
   TagPackVersLMap    	unsolvedRequirements;
   PackPackVersLMap   	conflictMap;
   ObsoleteList   	obsoleteMap;
   InstPackageMap       instPackageMap;

   // *.sel stuff
   Solver	  	*selSolver; // solving dependencies
   Solver	  	*selSaveSolver; // for saveStatus
   PackVersList   	selAdditionalPackages;
   TagPackVersLMap    	selUnsolvedRequirements;
   PackPackVersLMap   	selConflictMap;
   ObsoleteList   	selObsoleteMap;
   PackVersList   	selSaveAdditionalPackages;
   TagPackVersLMap    	selSaveUnsolvedRequirements;
   PackPackVersLMap   	selSaveConflictMap;
   ObsoleteList   	selSaveObsoleteMap;


   bool		   installSources; // Global Flag to install source-packages
   bool		   saveInstallSources;

   string packageInfoPath; // Path of the common.pkd and <language>.pkd
   string rootPath; // Root-Path ( update )
   bool update; // Flag, if this process is an update-process
   string yastPath; // Path of YaST-directory
   string commonPkd; // Name of common.pkd
   string language; // Selected language
   string duDir; // Filename ( with Path ) of the du.dir
   PartitionSizeMap partitionSizeMap; // Map of all partitions and their sizes
   PackageInstallMap packageInstallMap; //Map of all packages
   PackageInstallMap savePackageInstallMap; // for saveStatus
   SelInstallMap selInstallMap; //Map of all Selections
   SelInstallMap selSaveInstallMap; // for saveStatus

};


#endif // PackageAgent_h
