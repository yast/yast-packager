/*************************************************************
 *    
 *     YaST2      SuSE Labs                        -o)
 *     --------------------                        /\\
 *                                                _\_v
 *           www.suse.de / www.suse.com
 * ----------------------------------------------------------
 *
 * Author: 	  Stefan Schubert  <schubi@suse.de>
 *
 * File:	  RpmDb.h
 * Description:   main header file for RPM-Requests
 *
 * $Header$
 *
 *************************************************************/
   
/*
 * $Log$
 * Revision 1.1  2002/07/03 11:04:49  arvin
 * Initial revision
 *
 * Revision 1.1  2001/11/30 11:00:49  schubi
 * RPM agent added
 *
 * Revision 1.1  2001/11/12 16:57:25  schubi
 * agent for handling you
 *
 * Revision 1.9  2001/07/10 10:18:22  schubi
 * do not fetch rpm if it is already a valid version on the client
 *
 * Revision 1.8  2001/04/23 13:47:41  schubi
 * no more conficts with YaST1 defines
 *
 * Revision 1.7  2001/04/10 15:42:33  schubi
 * Reading dependencies from installed packages via RPM
 *
 * Revision 1.6  2000/08/09 15:50:30  schubi
 * new call: queryCurrentDBPath
 *
 * Revision 1.5  2000/08/04 13:29:38  schubi
 * Changes from 7.0 to 7.1; Sorry Klaus, I do not know anymore
 *
 * Revision 1.4  2000/05/30 15:43:43  kkaempf
 * fix include paths
 *
 * Revision 1.3  2000/05/18 14:01:21  schubi
 * removing liive-CD links and touch the directories
 *
 * Revision 1.2  2000/05/17 14:32:04  schubi
 * update Modus added after new cvs
 *
 * Revision 1.3  2000/05/11 11:47:55  schubi
 * update modus added
 *
 * Revision 1.2  2000/05/08 13:43:10  schubi
 * tested version
 *
 * Revision 1.1  2000/05/04 11:18:36  schubi
 * class to handle the rpm-DB; not testest
 *
 *
 */

// -*- C++ -*-

#ifndef RpmDb_h
#define RpmDb_h
#include <set>
#include <y2/ExternalProgram.h>
#include <pkg/pkginfo.h>

/**
 * @short Interface to the rpm program
 */

enum DbStatus { DB_OK, DB_NOT_FOUND, DB_OLD_VERSION , DB_NEW_CREATED,
                DB_ERROR_CREATED, DB_ERROR_CHECK_OLD_VERSION };


typedef set<string> FileList;



class RpmDb
{
public:

  /**
   * Create an new instance.
   * name_of_root The name of the install root
   */
  RpmDb(string name_of_root );

  /**
   * Clean up.
   */
  ~RpmDb();

   /**
    * Check package, if it is correctly installed.
    * Returns false, if an error has been occured.
    * "filelist" is a list of missing files
    */
   
   bool checkPackage ( string packageName, FileList &fileList );
   
  /**
   * Initialize the rpm database
   * If Flag "createNew" is set, than it will be created, if not
   * exist --> returns DbNewCreated if successfully created 
   */
  DbStatus initDatabase( bool createNew = false);

  /**
   * Creating a temporary rpm-database.
   * If copyOldRpm == true than the rpm-database from
   * /var/lib/rpm will be copied.
   */
  bool createTmpDatabase(bool copyOldRpm = false );

  /**
   * Installing the rpm-database to /var/lib/rpm, if the
   * current has been created by "createTmpDatabase".
   */
  bool installTmpDatabase( void );

   /**
    * Evaluate all installed packages WITH all Information
    * Returns false, if an error has been occured.	
    **/
   bool getInstalledPackagesInfo ( InstalledPackageMap &packageMap );
   
  /**  
   * Evaluate all installed packages
   * Returns false, if an error has been occured.
   */
  bool getInstalledPackages ( PackList &packageList );

  /**
   * Checking the source rpm <rpmpath>.rpm with rpm --chcksig and
   * the version number.
   */
   bool checkSourcePackage( string packagePath, string version = "" );
   
  /**
   * Query Version of a package.
   * Returns "" if an error has been occured.
   */
  string queryPackageVersion( string packageName );

  /**
   * Query Release of a package.
   * Returns "" if an error has been occured.
   */
  string queryPackageRelease( string packageName );

  /**
   * Query installation-time of a package.
   * Returns 0 if an error has been occured.
   */
  long queryPackageInstallTime( string packageName );

  /**
   * Query build-time of a package.
   * Returns 0 if an error has been occured.
   */
  long queryPackageBuildTime( string packageName );
  
  /**
   * Query summary of a package.
   * Returns "" if an error has been occured.
   */
  string queryPackageSummary( string packageName );
  
  
  /**
   * general query of a package
   * param: format The query format to use.
   *        package-name
   */
   string queryPackage(const char *format, string packageName);


   /**
    * Evaluate all files of a package which have been changed
    * since last installation or update.
    */
   bool queryChangedFiles ( FileList &fileList, string packageName );

   /**
    * Evaluate all files of a package which have been installed.
    * ( are listed in the rpm-DB )
    */
   bool queryInstalledFiles ( FileList &fileList, string packageName );

   /**
    * Evaluate all directories of a package which have been installed.
    * ( are listed in the rpm-DB )
    */
   bool queryDirectories ( FileList &fileList, string packageName );

   /**
    * Returns the current-path of the rpm-DB
    **/
   string queryCurrentDBPath ( void ) { return dbPath; };

   
private:

   
  /** 
   * The name of the install root.
   */
  string rootfs;


  /**
   * current Path of the DB-path ( without "packages.rpm" )
   */
   string dbPath; 
  
  /*
   * Flag that it is a temporary rpm-DB
   */
  bool temporary;;

  /**
   * The connection to the rpm process.
   */
  ExternalProgram *process;

  /**
   * Run rpm with the specified arguments and handle stderr.
   * @param n_opts The number of arguments
   * @param options Array of the arguments, @ref n_opts elements
   * @param stderr_disp How to handle stderr, merged with stdout by default
   */
  void run_rpm(int n_opts, const char *const *options,
	       ExternalProgram::Stderr_Disposition stderr_disp =
	       ExternalProgram::Stderr_To_Stdout);

      
  /**
   * Read a line from the general rpm query
   */
  bool systemReadLine(string &line);

  /**
   * Return the exit status of the general rpm process,
   * closing the connection if not already done.
   */
  int systemStatus();

  /**
   * Forcably kill the system process
   */
  void systemKill();
   

  /**
   * The exit code of the rpm process, or -1 if not yet known.
   */
  int exit_code;
};

#endif
