/*************************************************************
 *
 *     YaST2      SuSE Labs                        -o)
 *     --------------------                        /\\
 *                                                _\_v
 *           www.suse.de / www.suse.com
 * ----------------------------------------------------------
 *
 * File:	  RpmDb.cc
 *
 * Author: 	  Stefan Schubert <schubi@suse.de>
 *
 * Description:   Handling of the rpm - Request and rpm-dbs
 *
 * $Header$
 *
 *************************************************************/

/*
 * $Log$
 * Revision 1.1  2002/07/03 11:04:49  arvin
 * Initial revision
 *
 * Revision 1.2  2002/04/08 16:54:51  arvin
 * - fixes for gcc 3.1
 *
 * Revision 1.1  2001/11/30 11:00:49  schubi
 * RPM agent added
 *
 * Revision 1.1  2001/11/12 16:57:25  schubi
 * agent for handling you
 *
 * Revision 1.29  2001/07/10 10:18:22  schubi
 * do not fetch rpm if it is already a valid version on the client
 *
 * Revision 1.28  2001/07/04 16:50:47  arvin
 * - adapt for new automake/autoconf
 * - partly fix for gcc 3.0
 *
 * Revision 1.27  2001/07/04 14:25:05  schubi
 * new selection groups works besides the old
 *
 * Revision 1.26  2001/07/03 13:40:39  msvec
 * Fixed all y2log calls.
 *
 * Revision 1.25  2001/04/24 13:37:41  schubi
 * logging reduced; function for version evaluation
 *
 * Revision 1.24  2001/04/23 13:47:41  schubi
 * no more conficts with YaST1 defines
 *
 * Revision 1.23  2001/04/12 12:48:28  schubi
 * logging added in RpmDB; bufix while parsing common.pkd
 *
 * Revision 1.22  2001/04/10 15:42:33  schubi
 * Reading dependencies from installed packages via RPM
 *
 * Revision 1.21  2001/01/16 20:12:45  schubi
 * memory overflow int getInstalledPackages
 *
 * Revision 1.20  2001/01/13 15:41:08  schubi
 * bugfix in backup changed files
 *
 * Revision 1.19  2000/12/14 16:42:44  schubi
 * bugfix in querypackage
 *
 * Revision 1.18  2000/12/14 09:31:48  schubi
 * return more information, if there are double entries in the DB
 *
 * Revision 1.17  2000/12/10 15:23:42  schubi
 * descructor call changed
 *
 * Revision 1.16  2000/10/05 14:36:16  schubi
 * logging changed
 *
 * Revision 1.15  2000/09/18 10:29:24  schubi
 * bugfixes while installing tmp-rpm-DB
 *
 * Revision 1.14  2000/09/15 16:32:12  schubi
 * bugfixes while creating tmp-rpm-DB
 *
 * Revision 1.13  2000/08/04 13:29:38  schubi
 * Changes from 7.0 to 7.1; Sorry Klaus, I do not know anymore
 *
 * Revision 1.12  2000/07/07 14:48:06  schubi
 * setenv( RPM_IgnoreFailedSymlinks, 1, 1 ) added; logging changed
 *
 * Revision 1.11  2000/07/06 17:31:56  schubi
 * installTmpDatabase returns true, if no temp.DB have been installed
 *
 * Revision 1.10  2000/07/04 13:26:06  schubi
 * removing links to S.u.S.E works now correctly
 *
 * Revision 1.9  2000/07/03 12:42:47  schubi
 * checking only links not the installed files of a package
 *
 * Revision 1.8  2000/07/02 15:59:59  schubi
 * removing ExternalProcess for multiline-requests
 *
 * Revision 1.7  2000/06/30 16:41:10  schubi
 * bug fixes
 *
 * Revision 1.6  2000/06/28 18:44:18  schubi
 * loggin inserted
 *
 * Revision 1.5  2000/06/27 16:02:41  schubi
 * save rpm-DB
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
 */

#include <sys/stat.h>
#include <unistd.h>
#include <string.h>

#include "RpmDb.h"
#include <y2/ExternalDataSource.h>
#include <ycp/y2log.h>

#define ORIGINALRPMPATH "/var/lib/rpm/"
#define RPMPATH "/var/lib/"
#define RPMDBNAME "packages.rpm"

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



/****************************************************************/
/* public member-functions					*/
/****************************************************************/

/*-------------------------------------------------------------*/
/* creates a RpmDb					       */
/*-------------------------------------------------------------*/
RpmDb::RpmDb(string name_of_root)
{
   rootfs = name_of_root;
   process = 0;
   exit_code = -1;
   temporary = false;
   dbPath = "";
   setenv( "RPM_IgnoreFailedSymlinks", "1", 1 );
}

/*--------------------------------------------------------------*/
/* Cleans up						       	*/
/*--------------------------------------------------------------*/
RpmDb::~RpmDb()
{
   y2milestone ( "~RpmDb()" );

   if ( process )
      delete process;

   process = NULL;

   if ( temporary )
   {
      // Removing all files of the temporary DB
      string command = "rm -R ";

      command += dbPath;
      system ( command.c_str() );
   }

   y2milestone ( "~RpmDb() end" );
}


/*--------------------------------------------------------------*/
/* Initialize the rpm database					*/
/* If Flag "createNew" is set, than it will be created, if not	*/
/* exist --> returns DbNewCreated if successfully created 	*/
/*--------------------------------------------------------------*/
DbStatus RpmDb::initDatabase( bool createNew )
{
    string       dbFilename = rootfs;
    struct stat  dummyStat;
    DbStatus	 dbStatus = DB_OK;

    y2debug( "calling initDatabase" );

    dbFilename = dbFilename + ORIGINALRPMPATH + RPMDBNAME;
    if (  stat( dbFilename.c_str(), &dummyStat ) != -1 )
    {
       // DB found
       dbPath = ORIGINALRPMPATH;
       y2debug( "Setting dbPath to %s", dbPath.c_str() );
    }
    else
    {
       y2error( "dbFilename not found %s", dbFilename.c_str() );

       // DB not found
       dbStatus = DB_NOT_FOUND;

       if ( createNew )
       {
	  // New rpm-DB will be created
	  create_directories(rootfs + ORIGINALRPMPATH);
	  const char *const opts[] = { "--initdb" };
	  run_rpm(sizeof(opts) / sizeof(*opts), opts);
	  if ( systemStatus() != 0 )
	  {
	     // error
	     dbStatus = DB_ERROR_CREATED;
	  }
	  else
	  {
	     dbStatus = DB_NEW_CREATED;
	  }
       }
    }

    if ( dbStatus == DB_OK )
    {
       // Check, if it is an old rpm-Db
       const char *const opts[] = { "-q", "rpm" };
       string output;

       run_rpm(sizeof(opts) / sizeof(*opts), opts);
       if ( !systemReadLine ( output ) )
       {
	  // error
	  dbStatus = DB_ERROR_CHECK_OLD_VERSION;
	  y2error( "Error occured while checking old version." );
       }
       else
       {
	  if ( output.find ( "old format database is present" ) !=
	       string::npos )
	  {
	     dbStatus = DB_OLD_VERSION;
	     y2warning( "RPM-Db on the system is old" );
	  }
	  else
	  {
	     if ( systemStatus() != 0 )
	     {
		// error
		dbStatus = DB_ERROR_CHECK_OLD_VERSION;
		y2error( "Error occured while checking old version." );
	     }
	  }
       }
    }

    return dbStatus;
}

/*--------------------------------------------------------------*/
/* Creating a temporary rpm-database.				*/
/* If copyOldRpm == true than the rpm-database from		*/
/* /var/lib/rpm will be copied.					*/
/*--------------------------------------------------------------*/
bool RpmDb::createTmpDatabase ( bool copyOldRpm )
{
   // searching a non-existing rpm-path
   int counter = 0;
   struct stat  dummyStat;
   string rpmPath;
   string saveDbPath = dbPath;
   bool ok = true;
   char number[10];

   number[0] = 0;

   rpmPath = rootfs + RPMPATH + "rpm.new";
   while (  stat( rpmPath.c_str(), &dummyStat ) != -1 )
   {
      // search free rpm-path
      sprintf ( number, "%d", ++counter);
      rpmPath = rootfs + RPMPATH + "rpm.new." + number;
   }

   if ( mkdir ( rpmPath.c_str(), S_IRWXU ) == -1 )
   {
      ok = false;
      y2error( "ERROR command: mkdir %s", rpmPath.c_str());

   }

   // setting global dbpath
   dbPath = RPMPATH;
   if ( counter == 0 )
   {
      dbPath = dbPath + "rpm.new";
   }
   else
   {
      dbPath = dbPath + "rpm.new." + number;
   }

   if ( ok )
   {
      const char *const opts[] = { "--initdb" };
      run_rpm(sizeof(opts) / sizeof(*opts), opts);
      if ( systemStatus() != 0 )
      {
	 // error
	 ok = false;
	 y2error( "ERROR command: rpm --initdb  --dbpath %s",
		  dbPath.c_str());
      }
   }

   if ( ok && copyOldRpm )
   {
      // copy old RPM-DB into temporary RPM-DB

      string command = "cp -a ";
      command = command + rootfs + ORIGINALRPMPATH + "* " +
	 rpmPath;

      if ( system ( command.c_str() ) == 0 )
      {
	 ok = true;
      }
      else
      {
	 ok = false;
	 y2error( "ERROR command: %s",
		  command.c_str());
      }

      if ( ok )
      {
	 const char *const opts[] = { "--rebuilddb" };
	 run_rpm(sizeof(opts) / sizeof(*opts), opts);
	 if ( systemStatus() != 0 )
	 {
	    // error
	    ok = false;
	    y2error( "ERROR command: rpm --rebuilddb  --dbpath %s",
		     dbPath.c_str());
	 }
      }
   }

   if ( ok )
   {
      temporary = true;
   }
   else
   {
      // setting global dbpath
      dbPath = saveDbPath;
   }

   return ( ok );
}

/*--------------------------------------------------------------*/
/* Installing the rpm-database to /var/lib/rpm, if the		*/
/* current has been created by "createTmpDatabase".		*/
/*--------------------------------------------------------------*/
bool RpmDb::installTmpDatabase( void )
{
   bool ok = true;
   string oldPath;
   struct stat  dummyStat;
   int counter = 1;

   y2debug( "calling installTmpDatabase" );

   if ( !temporary  )
   {
      y2debug( "RPM-database have not to be updated." );
      return ( true );
   }

   if ( dbPath.length() <= 0 )
   {
      y2error( "RPM-DB is not initialized." );
      return ( false );
   }

   if ( ok )
   {
      // creating path for saved rpm-DB
      oldPath = rootfs + RPMPATH + "rpm.old";
      while (  stat( oldPath.c_str(), &dummyStat ) != -1 )
      {
	 // search free rpm-path
	 char number[10];
	 sprintf ( number, "%d", counter++);
	 oldPath = rootfs + RPMPATH + "rpm.old." + number;
      }

      if ( mkdir ( oldPath.c_str(), S_IRWXU ) == -1 )
      {
	 y2error( "ERROR command: mkdir %s", oldPath.c_str());
	 ok = false;
      }
   }

   if ( ok )
   {
      // saving old rpm
      string command = "cp -a ";
      command = command + rootfs + ORIGINALRPMPATH + "* " +oldPath;

      if ( system ( command.c_str() ) == 0)
      {
	 ok = true;
      }
      else
      {
	 y2error( "ERROR command: %s", command.c_str());
	 ok = false;
      }
   }


   if ( ok )
   {
      string command = "cp -a ";
      command = command + rootfs + dbPath + "/* " +
	 rootfs + ORIGINALRPMPATH;

      if ( system ( command.c_str() ) == 0)
      {
	 ok = true;
      }
      else
      {
	 y2error( "ERROR command: %s", command.c_str());
	 ok = false;
      }
   }

   if ( ok )
   {
      // remove temporary RPM-DB
      string command = "rm -R ";

      command += rootfs + dbPath;
      system ( command.c_str() );

      temporary = false;
      dbPath = ORIGINALRPMPATH;
   }

   return ( ok );
}


/*--------------------------------------------------------------*/
/* Evaluate all installed packages				*/
/* Returns false, if an error has been occured.			*/
/*--------------------------------------------------------------*/
bool RpmDb::getInstalledPackages ( PackList &packageList )
{
   bool ok = true;

   const char *const opts[] = {
      "-qa",  "--queryformat", "%{RPMTAG_NAME}\\n"
     };

   packageList.clear();

   run_rpm(sizeof(opts) / sizeof(*opts), opts,
	   ExternalProgram::Discard_Stderr);

   if ( process == NULL )
      return false;

   string value;

   string output = process->receiveLine();

   while ( output.length() > 0 )
   {
      string::size_type ret;

      // extract \n
      ret = output.find_first_of ( "\n" );
      if ( ret != string::npos )
      {
	 value.assign ( output, 0, ret );
      }
      else
      {
	 value = output;
      }

      packageList.insert ( value );
      output = process->receiveLine();
   }

   if ( systemStatus() != 0 )
   {
      ok = false;
   }

   return ( ok );
}


/*--------------------------------------------------------------*/
/* Evaluate all installed packages WITH all Information		*/
/* Returns false, if an error has been occured.			*/
/*--------------------------------------------------------------*/
bool RpmDb::getInstalledPackagesInfo ( InstalledPackageMap &packageMap )
{
   bool ok = true;

   const char *const opts1[] = {
      "-qa",  "--queryformat", "%{RPMTAG_NAME};%{RPMTAG_VERSION}-%{RPMTAG_RELEASE};%{RPMTAG_INSTALLTIME};%{RPMTAG_BUILDTIME};%{RPMTAG_GROUP}\\n"
     };

   const char *const opts2[] = {
      "-qa",  "--queryformat", "%{RPMTAG_NAME};%{OBSOLETES};%{PROVIDES}\\n"
     };

   const char *const opts3[] = {
      "-qa",  "--queryformat", "%{RPMTAG_NAME};[ %{REQUIRENAME} %{REQUIREFLAGS} %{REQUIREVERSION}];[ %{CONFLICTNAME} %{CONFLICTFLAGS} %{CONFLICTVERSION}] \\n"
     };

   packageMap.clear();

   run_rpm(sizeof(opts1) / sizeof(*opts1), opts1,
	   ExternalProgram::Discard_Stderr);

   if ( process == NULL )
      return false;

   string value;

   string output = process->receiveLine();

   while ( output.length() > 0 )
   {
      string::size_type ret;

      // extract \n
      ret = output.find_first_of ( "\n" );
      if ( ret != string::npos )
      {
	 value.assign ( output, 0, ret );
      }
      else
      {
	 value = output;
      }

      // parse line
      string::size_type begin;
      string::size_type end;
      const string 	seperator(";");
      int counter = 1;
      InstalledPackageElement package;

      begin = value.find_first_not_of ( seperator );
      while ( begin != string::npos )
      {
	 // each entry separated by ;

	 end = value.find_first_of ( seperator, begin );
	 if ( end == string::npos )
	 {
	    // end of line
	    end = value.length();
	 }
	 switch ( counter )
	 {
	    case 1:
	       package.packageName = value.substr ( begin, end-begin );
	       break;
	    case 2:
	       package.version = value.substr ( begin, end-begin );
	       break;
	    case 3:
	       package.installtime = atol(
				(value.substr ( begin, end-begin )).c_str());
	       break;
	    case 4:
	       package.buildtime = atol(
				(value.substr ( begin, end-begin )).c_str());
	       break;
	    case 5:
	       package.rpmgroup = value.substr ( begin, end-begin );
	       break;
	   default:
	      break;
	 }
	 counter++;
	 // next entry
	 begin = value.find_first_not_of ( seperator, end );
      }

      packageMap.insert(pair<const string, const InstalledPackageElement >
			( package.packageName, package ) );
      output = process->receiveLine();
   }

   if ( systemStatus() != 0 )
   {
      ok = false;
   }

   // Evaluate obsoletes and provides

   if ( ok )
   {
         run_rpm(sizeof(opts2) / sizeof(*opts2), opts2,
	   ExternalProgram::Discard_Stderr);

	 if ( process == NULL )
	    ok = false;
   }

   if ( ok )
   {

      output = process->receiveLine();

      while ( output.length() > 0 )
      {
	 string::size_type ret;

	 // extract \n
	 ret = output.find_first_of ( "\n" );
	 if ( ret != string::npos )
	 {
	    value.assign ( output, 0, ret );
	 }
	 else
	 {
	    value = output;
	 }

	 // parse line
	 string::size_type begin;
	 string::size_type end;
	 const string 	seperator(";");
	 int counter = 1;
	 InstalledPackageElement *package = NULL;
	 InstalledPackageMap::iterator pos;

	 begin = value.find_first_not_of ( seperator );
	 while ( begin != string::npos )
	 {
	    // each entry separated by ;

	    end = value.find_first_of ( seperator, begin );
	    if ( end == string::npos )
	    {
	       // end of line
	       end = value.length();
	    }
	    switch ( counter )
	    {
	       case 1:
		  pos = packageMap.find ( value.substr ( begin, end-begin ) );
		  if ( pos != packageMap.end() )
		  {
		     package = &(pos->second);
		  }
		  else
		  {
		     package = NULL;
		  }
		  break;
	    case 2:
	       if ( package != NULL &&
		    value.substr ( begin, end-begin ) != "(none)" )
	       {
		  package->obsoletes = value.substr ( begin, end-begin );
	       }
	       break;
	    case 3:
	       if ( package != NULL &&
		    value.substr ( begin, end-begin ) != "(none)" )
	       {
		  package->provides = value.substr ( begin, end-begin );
	       }
	       break;
	    default:
	       break;
	    }
	    counter++;
	    // next entry
	    begin = value.find_first_not_of ( seperator, end );
	 }
	 output = process->receiveLine();
      }
   }

   if ( systemStatus() != 0 )
   {
      ok = false;
   }


   // Evaluate requires and conflicts

   if ( ok )
   {
         run_rpm(sizeof(opts3) / sizeof(*opts3), opts3,
	   ExternalProgram::Discard_Stderr);

	 if ( process == NULL )
	    ok = false;
   }

   if ( ok )
   {
      output = process->receiveLine();

      while ( output.length() > 0 )
      {
	 string::size_type ret;

	 // extract \n
	 ret = output.find_first_of ( "\n" );
	 if ( ret != string::npos )
	 {
	    value.assign ( output, 0, ret );
	 }
	 else
	 {
	    value = output;
	 }

	 // parse line
	 string::size_type begin;
	 string::size_type end;
	 const string 	seperator(";");
	 int counter = 1;
	 InstalledPackageElement *package = NULL;
	 InstalledPackageMap::iterator pos;

	 begin = value.find_first_not_of ( seperator );
	 while ( begin != string::npos )
	 {
	    // each entry separated by ;

	    end = value.find_first_of ( seperator, begin );
	    if ( end == string::npos )
	    {
	       // end of line
	       end = value.length();
	    }
	    switch ( counter )
	    {
	       case 1:
		  pos = packageMap.find ( value.substr ( begin, end-begin ) );
		  if ( pos != packageMap.end() )
		  {
		     package = &(pos->second);
		  }
		  else
		  {
		     package = NULL;
		  }
		  break;
	    case 2:
	       if ( package != NULL )
	       {
		  package->requires = value.substr ( begin, end-begin );
	       }
	       break;
	    case 3:
	       if ( package != NULL )
	       {
		  package->conflicts = value.substr ( begin, end-begin );
	       }
	       break;
	    default:
	       break;
	    }
	    counter++;
	    // next entry
	    begin = value.find_first_not_of ( seperator, end );
	 }

	 output = process->receiveLine();
      }
   }

   if ( systemStatus() != 0 )
   {
      ok = false;
   }

   return ( ok );
}



/*--------------------------------------------------------------*/
/* Check package, if it is correctly installed.			*/
/* Returns false, if an error has been occured.			*/
/*--------------------------------------------------------------*/
bool RpmDb::checkPackage ( string packageName, FileList &fileList )
{
   bool ok = true;
   struct stat  dummyStat;


   const char *const opts[] = {
      "-ql", packageName.c_str()
     };

   run_rpm(sizeof(opts) / sizeof(*opts), opts,
	   ExternalProgram::Discard_Stderr);

   if ( process == NULL )
      return false;

   string value;
   fileList.clear();

   string output = process->receiveLine();

   while ( output.length() > 0)
   {
      string::size_type 	ret;

      // extract \n
      ret = output.find_first_of ( "\n" );
      if ( ret != string::npos )
      {
	 value.assign ( output, 0, ret );
      }
      else
      {
	 value = output;
      }

      // checking, if file exists
      if (  lstat( (rootfs+value).c_str(), &dummyStat ) == -1 )
      {
	 // file not found
	 ok = false;
	 fileList.insert ( value );
      }
      output = process->receiveLine();
   }

   if ( systemStatus() != 0 )
   {
      ok = false;
   }
   return ( ok );
}

/*--------------------------------------------------------------*/
/* Evaluate all files of a package which have to be installed.  */
/* ( are listed in the rpm-DB )					*/
/*--------------------------------------------------------------*/
bool RpmDb::queryInstalledFiles ( FileList &fileList, string packageName )
{
   bool ok = true;
   const char *const opts[] = {
      "-ql", packageName.c_str()
     };

   run_rpm(sizeof(opts) / sizeof(*opts), opts,
	   ExternalProgram::Discard_Stderr);

   if ( process == NULL )
      return false;

   string value;
   fileList.clear();

   string output = process->receiveLine();

   while ( output.length() > 0)
   {
      string::size_type 	ret;

      // extract \n
      ret = output.find_first_of ( "\n" );
      if ( ret != string::npos )
      {
	 value.assign ( output, 0, ret );
      }
      else
      {
	 value = output;
      }

      fileList.insert ( value );

      output = process->receiveLine();
   }

   if ( systemStatus() != 0 )
   {
      ok = false;
   }

   return ( ok );
}


/*------------------------------------------------------------------*/
/* Evaluate all directories of a package which have been installed. */
/* ( are listed in the rpm-DB )					    */
/*------------------------------------------------------------------*/
bool RpmDb::queryDirectories ( FileList &fileList, string packageName )
{
   bool ok = true;
   const char *const opts[] = {
      "-qlv", packageName.c_str()
     };

   run_rpm(sizeof(opts) / sizeof(*opts), opts,
	   ExternalProgram::Discard_Stderr);

   if ( process == NULL )
      return false;

   string value;
   char buffer[15000];
   size_t nread;
   fileList.clear();

   while (  nread = process->receive(buffer, sizeof(buffer)), nread != 0)
   {
      string output(buffer);
      string::size_type 	begin, end;

      begin = output.find_first_not_of ( "\n" );
      while ( begin != string::npos )
      {
	 // splitt the output in package-names
	 string value ="";
	 end = output.find_first_of ( "\n", begin );

	 // line-end ?
	 if ( end == string::npos )
	 {
	    end= output.length();
	 }

	 value.assign ( output, begin, end-begin );
	 begin = output.find_first_not_of ( "\n", end );

	 string::size_type fileBegin, fileEnd;
	 string dirname = "";
	 fileBegin = value.find_first_of ( '/' );
	 if ( fileBegin != string::npos )
	 {
	    fileEnd = value.find_first_of ( " ", fileBegin );

	    if ( fileEnd == string::npos )
	    {
	       // end reached
	       dirname.assign (value, fileBegin, string::npos);
	    }
	    else
	    {
	       dirname.assign ( value, fileBegin, fileEnd-fileBegin );
	    }

	    if ( value[0] != 'd' )
	    {
	       // is not a directory --> filename extract
	       fileEnd = dirname.find_last_of ( "/" );
	       dirname.assign ( dirname, 0, fileEnd );
	    }

	    fileList.insert ( dirname );
	 }
      }
   }

   if ( systemStatus() != 0 )
   {
      ok = false;
   }

   return ( ok );
}



/*--------------------------------------------------------------*/
/* Checking the source rpm <rpmpath>.rpm with rpm --chcksig and */
/* the version number.						*/
/*--------------------------------------------------------------*/
bool RpmDb::checkSourcePackage( string packagePath, string version )
{
   bool ok = true;

   if ( version != "" )
   {
      // Checking Version
      const char *const opts[] = {
	 "-qp", "--qf", "%{RPMTAG_VERSION}-%{RPMTAG_RELEASE} ",
	 packagePath.c_str()
      };
      run_rpm(sizeof(opts) / sizeof(*opts), opts,
	      ExternalProgram::Discard_Stderr);

      if ( process == NULL )
	 return false;

      string value;
      char buffer[4096];
      size_t nread;
      while ( nread = process->receive(buffer, sizeof(buffer)), nread != 0)
	 value.append(buffer, nread);
      if ( systemStatus() != 0 )
      {
	 // error
	 ok = false;
      }

      if ( value.length() >= 1 && value.at(value.length()-1) == ' ' )
      {
	 if ( value.length() > 1 )
	 {
	    // remove last blank
	    string dummy = value.substr(0,value.length()-1);
	    value = dummy;
	 }
	 else
	 {
	    value = "";
	 }
      }
      y2debug( "comparing version %s <-> %s", version.c_str(), value.c_str() );
      if ( version != value )
      {
	 ok = false;
      }
   }

   if ( ok )
   {
      // checking --checksig
      const char *const argv[] = {
	 "rpm", "--checksig",  packagePath.c_str(), 0
      };

      exit_code = -1;

      string output = "";
      unsigned int k;
      for ( k = 0; k < (sizeof(argv) / sizeof(*argv)) -1; k++ )
      {
	 output = output + " " + argv[k];
      }

      y2debug( "rpm command: %s", output.c_str() );

      if ( process != NULL )
      {
	 delete process;
	 process = NULL;
      }
      // Launch the program
      process = new ExternalProgram( argv, ExternalProgram::Discard_Stderr);


      if ( process == NULL )
      {
	 ok = false;
      }
      else
      {
	 if ( systemStatus() != 0 )
	 {
	    // error
	    ok = false;
	 }
      }
   }

   return ( ok );
}



/*--------------------------------------------------------------*/
/* Query Version of a package.					*/
/* Returns "" if an error has been occured.			*/
/*--------------------------------------------------------------*/
string RpmDb::queryPackageVersion( string packageName )
{
  return queryPackage("%{RPMTAG_VERSION}-%{RPMTAG_RELEASE} ", packageName );
}


/*--------------------------------------------------------------*/
/* Query Release of a package.					*/
/* Returns "" if an error has been occured.			*/
/*--------------------------------------------------------------*/
string RpmDb::queryPackageRelease( string packageName )
{
  return queryPackage("%{RPMTAG_RELEASE} ", packageName );
}


/*--------------------------------------------------------------*/
/* Query installation-time of a package.			*/
/* Returns 0 if an error has been occured.			*/
/*--------------------------------------------------------------*/
long RpmDb::queryPackageInstallTime( string packageName )
{
  string installTime = queryPackage("%{RPMTAG_INSTALLTIME} ", packageName );

  return ( atol ( installTime.c_str() ) );
}


/*--------------------------------------------------------------*/
/* Query build-time of a package.				*/
/* Returns 0 if an error has been occured.			*/
/*--------------------------------------------------------------*/
long RpmDb::queryPackageBuildTime( string packageName )
{
  string buildTime = queryPackage("%{RPMTAG_BUILDTIME} ", packageName );

  return ( atol ( buildTime.c_str() ) );
}


/*--------------------------------------------------------------*/
/* Query summary of a package.					*/
/* Returns "" if an error has been occured.			*/
/*--------------------------------------------------------------*/
string RpmDb::queryPackageSummary( string packageName )
{
  return queryPackage("%{RPMTAG_SUMMARY} ", packageName );
}


/*--------------------------------------------------------------*/
/* Query the current package using the specified query format	*/
/*--------------------------------------------------------------*/
string RpmDb::queryPackage(const char *format, string packageName)
{

  const char *const opts[] = {
    "-q", "--qf", format,  packageName.c_str()
  };
  run_rpm(sizeof(opts) / sizeof(*opts), opts, ExternalProgram::Discard_Stderr);

  if ( process == NULL )
     return "";

  string value;
  char buffer[4096];
  size_t nread;
  while ( nread = process->receive(buffer, sizeof(buffer)), nread != 0)
    value.append(buffer, nread);
  systemStatus();

  if ( value.length() >= 1 && value.at(value.length()-1) == ' ' )
  {
     if ( value.length() > 1 )
     {
	// remove last blank
	string dummy = value.substr(0,value.length()-1);
	value = dummy;
     }
     else
     {
	value = "";
     }
  }

  return value;
}


/*--------------------------------------------------------------*/
/* Evaluate all files of a package which have been changed	*/
/* since last installation or update.				*/
/*--------------------------------------------------------------*/
bool RpmDb::queryChangedFiles ( FileList &fileList, string packageName )
{
   bool ok = true;

   fileList.clear();


   const char *const opts[] = {
      "-V", packageName.c_str(),
      "--nodeps",
      "--noscripts",
      "--nomd5" };

   run_rpm(sizeof(opts) / sizeof(*opts), opts,
	   ExternalProgram::Discard_Stderr);

   if ( process == NULL )
      return false;

   string value;
   fileList.clear();

   string output = process->receiveLine();

   while ( output.length() > 0)
   {
      string::size_type 	ret;

      // extract \n
      ret = output.find_first_of ( "\n" );
      if ( ret != string::npos )
      {
	 value.assign ( output, 0, ret );
      }
      else
      {
	 value = output;
      }

      if ( value.length() > 12 &&
	   ( value[0] == 'S' || value[0] == 's' ||
	     ( value[0] == '.' &&
	       value[7] == 'T' )))
      {
	 // file has been changed
	 string filename;

	 filename.assign ( value, 11, value.length() - 11 );
	 filename = rootfs + filename;
	 fileList.insert ( filename );
      }

      output = process->receiveLine();
   }
   systemStatus();

   return ( ok );
}



/****************************************************************/
/* private member-functions					*/
/****************************************************************/

/*--------------------------------------------------------------*/
/* Run rpm with the specified arguments, handling stderr	*/
/* as specified  by disp					*/
/*--------------------------------------------------------------*/
void RpmDb::run_rpm(int n_opts, const char *const *options,
		       ExternalProgram::Stderr_Disposition disp)
{
  exit_code = -1;
  int argc = n_opts + 5 /* rpm --root <root> --dbpath <path> */
             + 1 /* NULL */;

  // Create the argument array
  const char *argv[argc];
  int i = 0;
  argv[i++] = "rpm";
  argv[i++] = "--root";
  argv[i++] = rootfs.c_str();
  argv[i++] = "--dbpath";
  argv[i++] = dbPath.c_str();
  for (int j = 0; j < n_opts; j++)
  {
    argv[i++] = options[j];
  }

  string output = "";
  int k;
  for ( k = 0; k < argc-1; k++ )
  {
     output = output + " " + argv[k];
  }
  argv[i] = 0;
  y2debug( "rpm command: %s", output.c_str() );

  if ( process != NULL )
  {
     delete process;
     process = NULL;
  }
  // Launch the program
  process = new ExternalProgram(argv, disp);
}

/*--------------------------------------------------------------*/
/* Read a line from the rpm process				*/
/*--------------------------------------------------------------*/
bool RpmDb::systemReadLine(string &line)
{
   if ( process == NULL )
      return false;

  line = process->receiveLine();
  if (line.length() == 0)
    return false;
  if (line[line.length() - 1] == '\n')
    line.erase(line.length() - 1);
  return true;
}

/*--------------------------------------------------------------*/
/* Return the exit status of the rpm process, closing the	*/
/* connection if not already done				*/
/*--------------------------------------------------------------*/
int RpmDb::systemStatus()
{
   y2debug( "calling systemStatus" );
   if ( process == NULL )
      return -1;

   exit_code = process->close();
   process->kill();
   delete process;
   process = 0;

  return exit_code;
}

/*--------------------------------------------------------------*/
/* Forcably kill the rpm process				*/
/*--------------------------------------------------------------*/
void RpmDb::systemKill()
{
  if (process) process->kill();
}
