/*************************************************************
 *
 *     YaST2      SuSE Labs                        -o)
 *     --------------------                        /\\
 *                                                _\_v
 *           www.suse.de / www.suse.com
 * ----------------------------------------------------------
 *
 * File:	  TargetpkgAgentCalls.cc
 *
 * Author: 	  Stefan Schubert <schubi@suse.de>
 *
 * Description:   Read/Execute/Write calls of you_targetpkg
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

#include <iostream>
#include <fstream>

#include <YCP.h>
#include <ycp/y2log.h>
#include <pkg/ConfigFile.h>
#include "RpmDb.h"
#include "TargetpkgAgent.h"

#define PATHLEN		256
#define RPMDIR "rpmrebuilddb."
#define PACKAGESRMP "packages.rpm"
#define BACKUPFILE "/YaSTBackupModifiedFiles"

/*-------------------------------------------------------------*/
/* Create all parent directories of @param name, as necessary  */
/*-------------------------------------------------------------*/
static void
create_directories(string name)
{
  size_t pos = 0;

  while (pos = name.find('/', pos + 1), pos != string::npos)
  {
     mkdir (name.substr(0, pos).c_str(), 0777);
  }
  mkdir (name.c_str(), 0777);
}

/*--------------------------------------------------------------------------*
 *  Returns the installed kernel-rpm-name ( like k_default )
 *--------------------------------------------------------------------------*/
YCPValue TargetpkgAgent::getInstalledKernel ( )
{
    PackList installedPackages;
    YCPValue ret = YCPNull();

    y2debug( "CALLING getInstalledKernel" );

    installedPackages.clear();

    if ( !rpmDb()->getInstalledPackages ( installedPackages ) )
    {
	ret = YCPError ( "getInstalledPackages not OK" );
	installedPackages.clear();
    }

    PackList::iterator posPackage;
    bool found = false;
    for ( posPackage = installedPackages.begin();
	  posPackage != installedPackages.end();
	  ++posPackage )
    {
	// evaluate all installed packages in order to get the kernel
	string dummy = *posPackage;
	if ( dummy.substr ( 0 , 2 ) == "k_" )
	{
	    ret = YCPString ( dummy );
	    found = true;
	}
    }

    if ( !found )
    {
	ret = YCPError ( "no installed kernel found" );
    }

    return ret;
}


/*--------------------------------------------------------------------------*
 * Returns the prgress status of rpm-rebuild.
 * It returns the progress from 0 to 100 percent.
 * If there have been found an error -1 will be returned.
 *--------------------------------------------------------------------------*/

static string rebuildPath ;
static bool rebuildWorking ;
static bool rebuildRmpFileFound ;


YCPValue TargetpkgAgent::getRebuildDbStatus( const bool start )
{
   int ret = -1;
   bool ok = true;

   y2debug( "CALLING getRebuildDbStatus" );

   if ( start )
   {
      rebuildPath = "";
      rebuildWorking = false;
      rebuildRmpFileFound = false;
   }

   if ( !rebuildWorking || rebuildPath == "" )
   {
      if ( !rebuildWorking )
      {
	 rebuildWorking = true;
	 rebuildPath = "";
	 rebuildRmpFileFound = false;
      }

      // evaluate the checking file
      string dbPath = targetroot + rpmDb()->queryCurrentDBPath();
      string::size_type pos = dbPath.find_last_of("/");

      if ( pos != string::npos )
      {
	 string dummy = "";
	 // checking if it is the last entry
	 while ( pos == dbPath.size()-1)
	 {
	    dummy = dbPath.substr(0,pos-1);
	    dbPath = dummy;
	    pos = dbPath.find_last_of("/");
	 }

	 // extract .../lib/rpm to ..../lib
	 if ( pos != string::npos )
	 {
	    dummy = dbPath.substr(0,pos);
	    dbPath = dummy;
	 }
      }

      y2milestone ( "DB-Path = %s", dbPath.c_str() );

      DIR *dir = opendir( dbPath.c_str() );

      if (!dir)
      {
	 y2error( "Can't open directory %s for reading",
		  dbPath.c_str());
	 ok = false;
      }
      else
      {
	 struct dirent *entry;
	 while ((entry = readdir(dir)))
	 {
	    if (!strcmp(entry->d_name, ".") ||
		!(strcmp(entry->d_name, ".."))) continue;

	    // check, if it is rpmrebuilddb.* - directory
	    string filename ( entry->d_name );
	    string::size_type pos = filename.find ( RPMDIR );

	    if ( pos != string::npos )
	    {
	       // rpm-rebuild-directory found
	       rebuildPath = dbPath + "/" + entry->d_name;
	       break;
	    }
	 }
	 closedir(dir);
      }
   }

   if ( rebuildPath == "" )
   {
      // at the beginning of the check
      ret = 0;
   }
   else
   {
      string filename = rebuildPath + "/" + PACKAGESRMP;
      struct stat check;
      y2milestone("searching file %s", filename.c_str() );
      if ( stat ( filename.c_str(), &check) == 0 )
      {
	 // file found
	 rebuildRmpFileFound = true;

	 // evaluate the progress
	 struct stat checkOrigin;
	 string origin = targetroot + rpmDb()->queryCurrentDBPath() + "/" +
	    PACKAGESRMP;
	 if ( stat ( origin.c_str(), &checkOrigin) == 0 )
	 {
	    // file found
	    float dummy = check.st_size;
	    dummy = ( dummy / checkOrigin.st_size ) *100;
	    ret = ( int ) dummy;
	 }
	 else
	 {
	    y2error( "RPM-DB-file %s not found", origin.c_str() );
	    ret = -1;
	 }
      }
      else
      {
	 y2milestone ( "file not found: %s", filename.c_str() );
	 if ( rebuildRmpFileFound )
	 {
	    // File has been existed and has been removed.
	    // So we are at the end of the rebuild

	    ret = 100;
	 }
	 else
	 {
	    // file will be created currently.
	    // So we are at the beginning of rebuild
	    ret = 0;
	 }
      }
   }
   y2milestone(	 "getRebuildDbstatus return %d percent", ret );

   return YCPInteger ( ret );

}

/*--------------------------------------------------------------------------*
 * Returns a map of all installed packages ( including all informtion )
 *--------------------------------------------------------------------------*/
YCPValue TargetpkgAgent::getAllPackageInfo()
{
    YCPMap ret;

    InstalledPackageMap packageMap;
    InstalledPackageMap::iterator posPackage;

    y2debug( "CALLING getAllPackageInfo" );

    rpmDb()->getInstalledPackagesInfo( packageMap );

    for ( posPackage = packageMap.begin();
	  posPackage != packageMap.end();
	  posPackage++ )
    {
	YCPList packageList;
	InstalledPackageElement installedPackage = posPackage->second;

	packageList->add( YCPString( installedPackage.version ) );

	packageList->add ( YCPInteger ( installedPackage.buildtime ) );

	packageList->add ( YCPInteger ( installedPackage.installtime ) );

	ret->add ( YCPString( installedPackage.packageName ),
		   packageList );
    }

    return ret;
}


/*--------------------------------------------------------------------------*
 * Save the configuration-files of a package.
 * Input : ["/var/adm/backup", "aaa_base" ]
 *     Name of the backup-directory, package-name
 * Return ok or !ok
 *--------------------------------------------------------------------------*/
YCPValue TargetpkgAgent::backupPackage( string packageName )
{
   YCPBoolean ret ( true );
   string backupFilename;
   struct stat  dummyStat;
   bool changedFilesFound = true;

   y2debug( "CALLING backupPackage" );

   if ( backupPath == "" )
   {
      y2error( "missing call .targetpkg.backupPath");
      ret = false;
      return ret;
   }

   FileList fileList;

   if ( !rpmDb()->queryChangedFiles ( fileList, packageName ) )
   {
      y2error( "Error while getting "
	       "changed files for package %s", packageName.c_str() );
      ret = false;
   }
   else
   {
      if ( fileList.size () <= 0 )
      {
	 y2debug( "package %s not changed -->"
		  " no backup", packageName.c_str() );
	 changedFilesFound = false;
      }
      else
      {
	 // save it to file
	 string filename = backupPath;
	 filename = filename + BACKUPFILE;
	 create_directories ( backupPath );
	 FileList::iterator pos;

	 std::ofstream fp ( filename.c_str() );

	 if ( !fp )
	 {
	    ret = false;
	    y2error( "ERROR opening : %s",
		     filename.c_str() );
	 }

	 if ( ret->value() )
	 {
	    for ( pos = fileList.begin(); pos != fileList.end(); ++pos )
	    {
		string name = (*pos).substr( targetroot.size() );
		if ( name[0] == '/' )
		{
		    // removing slash
		    name = name.substr( 1 );
		}
		y2debug( "saving file : %s",
			 name.c_str() );
		fp << name << std::endl;
	    }
	 }
      }
   }

   if ( ret->value() && changedFilesFound )
   {
      // build up archive name
      time_t     currentTime  = time( 0 );
      struct tm* currentLocalTime = localtime( &currentTime );
      string firstName;
      string counter;

      int    date = (currentLocalTime->tm_year + 1900) * 10000
	 + (currentLocalTime->tm_mon  + 1)    * 100
	 + currentLocalTime->tm_mday;
      char dateString[50];
      sprintf ( dateString, "%d", date );

      int num = 0;
      do {
	 char numString[20];
	 sprintf ( numString,"%d", num );
	 backupFilename =  backupPath+"/"+ packageName+"-"+
	    (string)dateString + "-" + (string)numString +".tgz";

      } while(  stat( backupFilename.c_str(), &dummyStat ) != -1
		&& num++ < 1000 );
   }

   if ( ret->value() && changedFilesFound )
   {
      string command = "(cd "+targetroot+"/ ; tar -c -z -h -P -f "+backupFilename+
	 " -T "+backupPath+BACKUPFILE+" --ignore-failed-read )";
      if ( system ( command.c_str() ) != 0 )
      {
	 y2error( "Failed: %s",
		  command.c_str() );
	 ret = false;
      }
      else
      {
	 y2debug( "TAR: %s --> OK",
		  command.c_str() );
      }

      string filename =  backupPath;
      filename +=  BACKUPFILE;
      unlink ( filename.c_str() );
   }

   return ret;
}


/*--------------------------------------------------------------------------*
 * Touch all directories of a package
 *--------------------------------------------------------------------------*/
YCPValue TargetpkgAgent::touchDirectories ( string packageName )
{
   YCPBoolean ret ( true );

   y2debug( "CALLING touchDirectories" );

   FileList fileList;
   FileList::iterator pos;

   if ( !rpmDb()->queryDirectories ( fileList, packageName ) )
   {
      y2error( "Error while getting "
	       "changed files for package %s", packageName.c_str() );
      ret = false;
   }
   else
   {
      // touch directories
      for ( pos = fileList.begin(); pos != fileList.end(); ++pos )
      {
	 string filename = targetroot + *pos;
	 utime ( filename.c_str(), 0 );
      }
   }

   return ( ret );
}


/*--------------------------------------------------------------------------*
 * Remove all links ( like links to live-CD ) of a package.
 *--------------------------------------------------------------------------*/
YCPValue TargetpkgAgent::removePackageLinks( string packageName )
{
   YCPBoolean ret ( true );
   struct stat  check;

   y2debug( "CALLING removePackageLinks" );

   FileList fileList;
   FileList::iterator pos;

   if ( !rpmDb()->queryInstalledFiles ( fileList, packageName ) )
   {
      y2warning( "No files found "
		 "for package %s", packageName.c_str() );
      ret = false;
   }
   else
   {
      // checking links
      for ( pos = fileList.begin(); pos != fileList.end(); ++pos )
      {
	 bool toDelete = false;
	 string filename = targetroot + *pos;
	 if ( lstat ( filename.c_str(), &check ) == 0 &&
	      S_ISLNK ( check.st_mode ) )
	 {
	    // is a link --> read the link
	    char sourceBuffer[PATHLEN+1];
	    int len = readlink ( filename.c_str(), sourceBuffer, PATHLEN );
	    if ( len > 0 )
	    {
	       // check, if it has to delete
	       sourceBuffer[len] = 0;
	       string filenameSource = sourceBuffer;

	       if ( filenameSource.find ( "S.u.S.E" ) != string::npos )
	       {
		  toDelete = true;
	       }
#if defined __GNUC__ && __GNUC__ >= 3
	       if (filenameSource.compare (0, strlen ("/lib"), "/lib") == 0)
#else
	       if (filenameSource.compare ("/lib", 0, strlen ("/lib")) == 0)
#endif
	       {
		  toDelete = false;
	       }
	       if ( filenameSource.find ( "vmlinuz" ) != string::npos )
	       {
		  toDelete = false;
	       }
	    }

	    if ( toDelete )
	    {
	       y2debug( "Removing link to %s",
			sourceBuffer );
	       y2debug( "link: %s",
			filename.c_str() );
	       unlink ( filename.c_str() );
	    }
	    else
	    {
	       y2debug(	 "DO NOT remove link to %s",
			 sourceBuffer );
	    }
	 }
      }
   }

   return ret;
}


/*-------------------------------------------------------------------------*
 *  Updating RPM-DB if needed
 *-------------------------------------------------------------------------*/
YCPValue TargetpkgAgent::updateRpmDb( )
{
   YCPBoolean ret ( false );

   y2debug( "CALLING updateRpmDb" );

   ret = rpmDb()->installTmpDatabase();

   return ret;
}


/*-------------------------------------------------------------------------*
 *  Starting: rpm --rebuilddb
 *-------------------------------------------------------------------------*/
bool TargetpkgAgent::startRebuildDb( )
{
    bool ok = true;

    if ( mainscragent )
    {
	YCPPath path = ".target.bash";
	YCPPath backgroundpath = ".target.bash_background";
	YCPString value ( "/bin/rm -R "
		      + targetroot
		      + "/var/lib/rpmrebuilddb.*" );

	// removing old rpm rebuild trees
	YCPValue ret = mainscragent->Execute( path, value );

	//starting rebuild process
	string command = "ulimit -s unlimited; /bin/rpm --rebuilddb --root "
		 + targetroot + " --dbpath "
		 + rpmDb()->queryCurrentDBPath();
	value = YCPString ( command );

	ret = mainscragent->Execute( backgroundpath, value );
	if ( ret->isInteger() )	// success
	{
	    if (  ret->asInteger()->value() >= 0 )
	    {
		y2milestone( "%s ok", command.c_str() );
	    }
	    else
	    {
		y2error( "%s", command.c_str() );
		ok = false;
	    }
	}
	else
	{
	    y2error("<.target.bash_background> System agent returned nil.");
	    ok = false;
	}
    }
    else
    {
	y2error("No system agent installed");
	ok = false;
    }

    return ok;
}
