#!/usr/bin/perl -w

#
# Module:	OneClickInstallStandard.pm
# Authors:	Lukas Ocilka <locilka@suse.cz>
# Summary:	Module for parsing One Click Install Standard
#		http://en.opensuse.org/Standards/One_Click_Install
#

package OneClickInstallStandard;

use strict;

use XML::Simple;

use YaPI;
use YaST::YCP;

my %config = (
    # evaluate everything as arrays
    ForceArray => 1,
    # remove the the first XML tag
    KeepRoot => 0,
    NoEscape => 1,
    NoIndent => 1,
    ForceContent => 1,
    ContentKey => '-content',
);

our %TYPEINFO;

##
# Converts XML to a list of maps with all repositories described in the XML content.
#
# @param XML content as descibed at http://en.opensuse.org/Standards/One_Click_Install
# @return list <map, <string, any> >
#
# @struct $[
#         "distversion" : "openSUSE Factory",
#         "url" : "full url of the repository (http://.../)",
#         "format" : "yast",
#         "recommended" : true,
#         "description" : "repository description",
#         "localized_description" : $[
#             "en_GB" : "repository description (localized to en_GB)",
#             ...
#         ],
#         "summary" : "repository summary",
#         "localized_summary" : $[
#             "en_GB" : "repository summary (localized to en_GB)",
#             ...
#         ],
#         "name" : "repository name",
#         "localized_name" : $[
#             "en_GB" : "repository name (localized to en_GB)",
#             ...
#         ],
#         "mirrors" : [
#             $[
#                 "url" : "full url of the mirror (http://.../)",
#                 "location" : "?",
#                 "score" : number,
#             ]
#             ...
#         ]
# ]
BEGIN {$TYPEINFO{GetRepositoriesFromXML} = ["function", ["list", ["map", "string", "any"]], "string"];}
sub GetRepositoriesFromXML ($) {
    my $class = shift;

    my $xmlfilecontent = shift || do {
	y2error ("First parameter needs to be a XML content");
	return undef;
    };

    my $xmlparser = new XML::Simple (%config);
    my $data = $xmlparser->XMLin ($xmlfilecontent);
    $xmlparser = undef;

    my $groups = $data->{'group'} || [];
    $data = undef;

    my @repos = ();
    my $repo = {};
    # default language is used when no 'language' string is defined
    my $default_lang = "en_US";

    foreach my $group (@{$groups}) {
	foreach my $one_repo_group (@{$group->{'repositories'}}) {
	    foreach my $one_repo (@{$one_repo_group->{'repository'}}) {
		$repo = {};
		$repo->{'distversion'} = $group->{'distversion'} || "";
		$repo->{'format'} = $one_repo->{'format'} || "";

		# fills up:
		#     * name, description, summary (string)
		#     * localized_name, localized_description, localized_summary (map <string, string>)
		foreach my $key ('name', 'description', 'summary') {
		    foreach my $repo_keys (@{$one_repo->{$key}}) {
			my $lang = $repo_keys->{'lang'} || $default_lang;
			$repo->{'localized_'.$key}->{$lang} = $repo_keys->{'content'} || "";
		    }
		    if (defined $repo->{'localized_'.$key}->{$default_lang}) {
			$repo->{$key} = $repo->{'localized_'.$key}->{$default_lang};
		    }
		}

		my @mirrors = ();
		foreach my $repo_url (@{$one_repo->{'url'}}) {
		    # default url
		    if (! defined $repo_url->{'score'} && ! defined $repo_url->{'location'}) {
			$repo->{'url'} = $repo_url->{'content'} || "";
		    } else {
			push @mirrors, {
			    'url' => $repo_url->{'content'} || "",
			    'score' => $repo_url->{'score'} || "",
			    'location' => $repo_url->{'location'} || "",
			};
		    }
		}
		if (scalar(@mirrors) > 0) {
		    @{$repo->{'mirrors'}} = @mirrors;
		}

		push @repos, $repo;
	    }
	}
    }

    return \@repos;
}

$! = 1;
