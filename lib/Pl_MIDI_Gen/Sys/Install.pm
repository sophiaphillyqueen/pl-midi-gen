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
  
  $this = shift(@_);
  $lc_args = [@_];
  
  # Obtain the home directory and executable search path.
  $lc_home = $ENV{'HOME'};
  $lc_path = $ENV{'PATH'} // '';
  
  $lc_prefix = undef;
  
  if ( !defined($lc_home) || $lc_home eq '' )
  {
    die "Cannot select MDGN installation prefix: HOME is not set.\n";
  }
  
  GetOptionsFromArray(
    $lc_args,
    'mdgn_dir=s'  => \$lc_prefix,
  ) or die("Invalid installation options.\n");
  
  # Search PATH in order, stopping at the first match.
  if ( !defined($lc_prefix) )
  {
    foreach $lc_each (split(/:/,$lc_path))
    {
      if ( $lc_each eq "$lc_home/.local/bin" )
      {
        $lc_prefix = "$lc_home/.local/mdgn";
        last;
      }
    
      if ( $lc_each eq "$lc_home/local/bin" )
      {
        $lc_prefix = "$lc_home/local/mdgn";
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


1;