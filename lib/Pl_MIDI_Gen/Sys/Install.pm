package Pl_MIDI_Gen::Sys::Install;
use strict;
use warnings;
use FindBin qw($RealBin);
use JSON::PP ();
use Getopt::Long qw(GetOptionsFromArray);


sub do_install {
  my $this;
  my $lc_home;
  my $lc_path;
  my $lc_each;
  my $lc_prefix;
  my $lc_packd;
  my $lc_pknom;
  my $lc_args;
  my $lc_stage; # Stage location
  my $lc_stgd;  # Is the stage location specified?
  my $lc_archive;
  
  $this = shift(@_);
  $lc_args = [@_];
  
  # Obtain the home directory and executable search path.
  $lc_home = $ENV{'HOME'};
  $lc_path = $ENV{'PATH'} // '';
  
  if ( !defined($lc_home) || $lc_home eq '' )
  {
    die "Cannot select MDGN installation prefix: HOME is not set.\n";
  }
  
  $lc_prefix = undef;
  $lc_stage = undef;
  $lc_archive = 0;
  
  GetOptionsFromArray(
    $lc_args,
    'stage=s'  => \$lc_stage,
    'mdgn_dir=s'  => \$lc_prefix,
    'archive'    => \$lc_archive,
  ) or die("Invalid installation options.\n");
  
  # Was the stage specified?
  $lc_stgd = 1;
  if ( !(defined($lc_stage)) )
  {
    $lc_stgd = 0;
    $lc_stage = '';
  }
  
  # If the stage location is set, that changes the
  # default location of the prefix.
  if ( !defined($lc_prefix) )
  {
    if ( $lc_stgd )
    {
      $lc_prefix = '/usr/lib/mdgn';
    }
  }
  
  # Search PATH in order, stopping at the first match.
  if ( !defined($lc_prefix) )
  {
    foreach $lc_each (split(/:/,$lc_path))
    {
      if ( $lc_each eq "$lc_home/.local/bin" )
      {
        $lc_prefix = "$lc_home/.local/lib/mdgn";
        last;
      }
    
      if ( $lc_each eq "$lc_home/local/bin" )
      {
        $lc_prefix = "$lc_home/local/lib/mdgn";
        last;
      }
    }
  }
  
  # Failure to find either directory is fatal.
  if ( !defined($lc_prefix) )
  {
    die "Cannot select MDGN installation prefix: neither "
      . "$lc_home/.local/bin nor $lc_home/local/bin "
      . "was found in PATH.\n";
  }
  
  if ( !(chdir($RealBin)) )
  {
    die "\nInstall script couldn't enter its own home directory!!!\n\n";
  }
  
  # Prepare the archive if necessary.
  if ( $lc_archive )
  {
    return $this->prep_archive();
  }
  
  # Report the selected prefix.
  #print "$lc_prefix\n";
  
  system('rm','-rf','build');
  if( ( -d 'build') || ( -f 'build' ) )
  {
    die "\nCouldn't delete old `build` directory.\n\n";
  }
  system('mkdir','build');
  if( !( -d 'build' ) )
  {
    die "\nCouldn't create new `build` directory.\n\n";
  }
  
  
  {
    # Load the package information from JSON.
    my $lc2_fh;
    my $lc2_json;
  
    open($lc2_fh,'<:raw','cont/pack-data.json')
      or die "Cannot open 'cont/pack-data.json': $!\n";
  
    # Read the entire file.
    local $/;
    $lc2_json = <$lc2_fh>;
  
    close($lc2_fh)
      or die "Cannot close pack-data.json: $!\n";
  
    # Decode the JSON into our package data variable.
    $lc_packd = JSON::PP->new->utf8->decode($lc2_json);
  }
  
  $lc_pknom = $lc_packd->{'name'};
  if ( ( !(defined($lc_pknom)) ) || ( ref($lc_pknom) ne '' ) || ( $lc_pknom eq '' ) )
  {
    die "\nPACKAGE HAS NO NAME TO SPEAK OF!!!!!\n\n";
  }
  
  system('cp','-r','cont',('build/' . $lc_pknom));
  system('rm','-rf',($lc_prefix . '/'. $lc_pknom));
  system('mkdir','-p',$lc_prefix);
  system('cp','-r',('build/' . $lc_pknom),($lc_prefix . '/.'));
  
}


use POSIX ();

sub prep_archive {
  # Create a distribution archive from the committed
  # Git revision, rather than the working tree.
  #
  # Returns the pathname of the completed archive.
  # All failures are fatal.

  my $this;
  my $lc_commit;
  my $lc_packd;
  my $lc_result;

  $this = shift(@_);

  # Prepare the workspace and obtain the committed source.
  $this->_reset_build();
  $lc_commit = $this->_extract_git_head();

  # Update the staged metadata and create the archive.
  $lc_packd = $this->_prepare_pack_data($lc_commit);
  $lc_result = $this->_create_tarball($lc_packd);

  return $lc_result;
}


sub _reset_build {
  # Remove prior output and prepare the fixed staging
  # directory at build/staging/source.

  my $this;

  $this = shift(@_);

  if ( system('rm','-rf','build') != 0 )
  {
    die "Cannot remove old build directory.\n";
  }

  if ( system('mkdir','-p','build/staging/source') != 0 )
  {
    die "Cannot create build staging directory.\n";
  }

  return;
}


sub _extract_git_head {
  # Extract the current committed revision into staging,
  # rather than extracting the current working tree.
  #
  # Returns the complete Git object ID for the revision.

  my $this;
  my $lc_commit;

  $this = shift(@_);

  # Identify the exact commit used for the source archive.
  $lc_commit = `git rev-parse --verify HEAD`;
  if ( $? != 0 ) { die "Cannot identify Git HEAD.\n"; }

  chomp($lc_commit);

  if ( $lc_commit !~ /\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/ )
  {
    die "Git returned an invalid commit object ID.\n";
  }

  # Use Git to capture the files in that commit.
  if ( system('git','archive','--format=tar',
         '--output=build/staging/source.tar',$lc_commit) != 0 )
  {
    die "Cannot archive committed Git files.\n";
  }

  # Extract those files beneath the fixed staging directory.
  if ( system('tar','-xf','build/staging/source.tar',
         '-C','build/staging/source') != 0 )
  {
    die "Cannot extract committed Git files.\n";
  }

  # The intermediate tar file is no longer needed.
  unlink('build/staging/source.tar')
    or die "Cannot remove temporary source archive: $!\n";

  return $lc_commit;
}


sub _prepare_pack_data {
  # Load the committed package metadata from staging.
  #
  # Mark the staged copy as packaged and record the
  # source commit ID.
  #
  # Generate a timestamp only for development versions.
  #
  # Returns the completed metadata as a hash reference.

  my $this;
  my $lc_commit;
  my $lc_file;
  my $lc_fh;
  my $lc_json;
  my $lc_packd;
  my $lc_name;
  my $lc_version;

  $this = shift(@_);
  $lc_commit = shift(@_);

  $lc_file = 'build/staging/source/cont/pack-data.json';

  # Read the metadata included in Git HEAD.
  open($lc_fh,'<:raw',$lc_file)
    or die "Cannot read staged package metadata: $!\n";

  {
    local $/;
    $lc_json = <$lc_fh>;
  }

  close($lc_fh)
    or die "Cannot close staged metadata: $!\n";

  $lc_packd = JSON::PP->new->utf8->decode($lc_json);

  if ( ref($lc_packd) ne 'HASH' )
  {
    die "Package metadata must be a JSON object.\n";
  }

  # Check the fields used in directory and archive names.
  $lc_name = $lc_packd->{'name'};
  $lc_version = $lc_packd->{'version'};

  if ( !defined($lc_name) || ref($lc_name) || $lc_name eq ''
       || $lc_name eq '.' || $lc_name eq '..'
       || $lc_name =~ m{[/\x00]} )
  {
    die "Invalid package name.\n";
  }

  if ( !defined($lc_version) || ref($lc_version)
       || $lc_version eq '' || $lc_version =~ m{[/\x00]} )
  {
    die "Invalid package version.\n";
  }

  # Refuse to package an already-packaged distribution.
  if ( $lc_packd->{'packaged'} )
  {
    die "Refusing to repackage an already packaged distribution.\n";
  }

  # Modify only the staged metadata, leaving HEAD untouched.
  $lc_packd->{'packaged'} = 1;
  $lc_packd->{'gitcommit'} = $lc_commit;

  if ( $lc_packd->{'stable'} )
  {
    # Stable releases have no development timestamp.
    delete($lc_packd->{'tstamp'});
  } else {
    # Development releases receive a UTC timestamp.
    $lc_packd->{'tstamp'} = POSIX::strftime(
      '%Y-%m-%d--%H-%M-%SZ',gmtime(time())
    );
  }

  # Write the finalized metadata back to the staged copy.
  $lc_json = JSON::PP->new->utf8->canonical->pretty->encode($lc_packd);

  open($lc_fh,'>:raw',$lc_file)
    or die "Cannot write staged package metadata: $!\n";

  print {$lc_fh} $lc_json
    or die "Cannot write package metadata contents: $!\n";

  close($lc_fh)
    or die "Cannot close staged metadata: $!\n";

  return $lc_packd;
}


sub _create_tarball {
  # Package the staged source beneath one top-level
  # directory named after the bundle, including its
  # version and (if applicable) development timestamp.
  #
  # Remove the staging directory after successful packaging.
  #
  # Returns the pathname of the completed .tar.gz archive.

  my $this;
  my $lc_packd;
  my $lc_name;
  my $lc_archive;

  $this = shift(@_);
  $lc_packd = shift(@_);

  # Construct the directory name from the package metadata.
  $lc_name = $lc_packd->{'name'} . '-' . $lc_packd->{'version'};

  if ( !$lc_packd->{'stable'} )
  {
    # Development versions include the timestamp.
    $lc_name .= '--' . $lc_packd->{'tstamp'};
  }

  # Construct the corresponding archive filename.
  $lc_archive = 'build/' . $lc_name . '.tar.gz';

  # Give the staged root its distribution name.
  rename('build/staging/source',('build/staging/' . $lc_name))
    or die "Cannot name staged bundle directory: $!\n";

  # Package everything beneath the bundle-named directory.
  if ( system('tar','-czf',$lc_archive,'-C','build/staging',$lc_name) != 0 )
  {
    die "Cannot create MDGN distribution archive.\n";
  }

  # Leave only the completed archive inside build.
  if ( system('rm','-rf','build/staging') != 0 )
  {
    die "Cannot remove completed staging directory.\n";
  }

  return $lc_archive;
}


1;