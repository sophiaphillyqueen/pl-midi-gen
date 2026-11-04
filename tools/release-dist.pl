use strict;
use warnings;

use Cwd qw(getcwd);
use ExtUtils::Manifest qw(manifind manicopy maniskip);
use File::Copy qw(copy);
use File::Spec;
use File::Temp qw(tempdir);
use POSIX qw(strftime);

# Build a distribution from current filesystem contents
# All version changes and packaging occur inside staging
# Git and the existing MANIFEST do not control file selection

my $lc_root;
my $lc_stage;
my $lc_files;
my $lc_skip;
my $lc_file;
my $lc_module;
my $lc_in;
my $lc_out;
my $lc_source;
my $lc_stamp;
my $lc_changed;
my $lc_command;
my @lc_archives;

$lc_root = getcwd();

# Create an automatically cleaned temporary staging directory
$lc_stage = tempdir(
  'pl-midi-gen-XXXXXX',
  TMPDIR => 1,
  CLEANUP => 1
);

# Discover files directly from the filesystem
# Exclude standard Perl build artifacts and generated releases
$lc_files = manifind();
$lc_skip = maniskip($ExtUtils::Manifest::DEFAULT_MSKIP);

foreach $lc_file ( keys %$lc_files )
{
  delete $lc_files->{$lc_file} if $lc_skip->($lc_file);
  delete $lc_files->{$lc_file} if $lc_file eq 'MANIFEST';
  delete $lc_files->{$lc_file} if $lc_file =~ m{\APl_MIDI_Gen-\d};
}

# Make independent copies, never hard links to source files
manicopy($lc_files, $lc_stage, 'cp');

# Read the version declaration from the staged module
$lc_module = File::Spec->catfile(
  $lc_stage, 'lib', 'Pl_MIDI_Gen.pm'
);

open($lc_in, '<', $lc_module)
  or die "Cannot read staged module: $!\n";

{
  local $/;
  $lc_source = <$lc_in>;
}

close($lc_in)
  or die "Cannot close staged module: $!\n";

# Timestamp development versions using UTC
# Leave stable versions unchanged
$lc_stamp = strftime('%Y%m%d%H%M%S', gmtime());

$lc_changed = (
  $lc_source =~ s/(\bour\s+\$VERSION\s*=\s*['"]\d+(?:\.\d+)*_)\d+(?=['"])/$1$lc_stamp/
);

# Write only to the staged module, never the original
if ( $lc_changed )
{
  open($lc_out, '>', $lc_module)
    or die "Cannot update staged version: $!\n";

  print {$lc_out} $lc_source
    or die "Cannot write staged version: $!\n";

  close($lc_out)
    or die "Cannot close staged version: $!\n";
}

# Generate the manifest and archive inside staging
chdir($lc_stage)
  or die "Cannot enter staging directory: $!\n";

$ENV{'PL_MIDI_GEN_RELEASE_STAGE'} = 1;

foreach $lc_command (
  [$^X, 'Makefile.PL'],
  ['make', 'manifest'],
  ['make', 'test'],
  ['make', 'dist']
)
{
  system(@$lc_command) == 0
    or die "Packaging command failed: @$lc_command\n";
}

# Copy the completed distribution to the original directory
@lc_archives = glob('Pl_MIDI_Gen-*.tar.gz');

die "Expected one distribution archive\n"
  if @lc_archives != 1;

copy(
  $lc_archives[0],
  File::Spec->catfile($lc_root, $lc_archives[0])
) or die "Cannot copy finished archive: $!\n";

print "Created $lc_archives[0]\n";

