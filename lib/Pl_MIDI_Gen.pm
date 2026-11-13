# Pl_MIDI_Gen: Facilitates loading and constructing MIDI generation engines, instrument controllers, and library utilities.
# Copyright (C) 2026  Sophia Elizabeth Shapira
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, see <https://www.gnu.org/licenses/>.

package Pl_MIDI_Gen;

use strict;
use warnings;

our $VERSION = '0.01_00';

use Cwd qw(abs_path);
use Scalar::Util qw(blessed);
use File::Basename qw(dirname);

# All state belongs to the class, not to an individual
# bartender object.
my $initialized = 0;
my $external_namespace;
my $next_external_number = 1;
my %external_packages;


sub new {
  # Initialize the bartender on its first successful construction.
  # After that, ignore all constructor arguments and return an
  # empty object.
  #
  # Failed initialization returns undef and may be retried.

  my $this;
  my $lc_namespace;

  $this = shift(@_);

  if ( !$initialized )
  {
    # Only the initializing call requires exactly one valid
    # namespace argument.
    if ( scalar(@_) != 1 ) { return undef; }

    $lc_namespace = shift(@_);

    if ( !defined($lc_namespace) || ref($lc_namespace) )
    {
      return undef;
    }

    if ( $lc_namespace !~ /\A[A-Z][A-Za-z0-9_]*_[A-Za-z0-9]+\z/ )
    {
      return undef;
    }

    # Initialization has succeeded, so establish the shared
    # namespace and set the initialization flag.
    $external_namespace = $lc_namespace;
    $initialized = 1;
  }

  return bless( {}, ( ref($this) || $this ) );
}



sub find_bundle {
  # Locate an installed MDGN bundle by name.
  #
  # For each bin directory in PATH, examine its
  # sibling mdgn directory for the requested bundle.
  #
  # A bundle is recognized by the presence of
  # its pack-data.json file.
  #
  # Returns the canonical absolute pathname of the
  # first matching bundle directory, or undef if
  # the bundle cannot be found.

  my $this;
  my $lc_name;
  my $lc_path;
  my $lc_candidate;
  my $lc_result;

  $this = shift(@_);
  $lc_name = shift(@_);

  # Reject invalid bundle names.
  if ( !defined($lc_name) || ref($lc_name) )
  {
    return undef;
  }

  if ( $lc_name eq '' || $lc_name eq '.' || $lc_name eq '..'
       || $lc_name =~ m{[/\x00]} )
  {
    return undef;
  }

  # Search each eligible PATH entry in order.
  foreach $lc_path (split(/:/,($ENV{'PATH'} // '')))
  {
    # Only consider directories named bin.
    if ( $lc_path !~ m{(?:\A|/)bin/*\z} ) { next; }

    # Construct the corresponding bundle directory.
    $lc_candidate = dirname($lc_path) . '/mdgn/' . $lc_name;

    # The marker must be present.
    if ( !-f "$lc_candidate/pack-data.json" ) { next; }

    # Resolve the candidate to an absolute pathname.
    $lc_result = abs_path($lc_candidate);

    if ( defined($lc_result) && -d $lc_result )
    {
      return $lc_result;
    }
  }

  # No matching bundle was found.
  return undef;
}



sub fromus {
  # Load a plug-in from Pl_MIDI_Gen's own module namespace.
  #
  # Pass constructor arguments through unchanged after the
  # plug-in's short package name.

  my $this;
  my $lc_pack;
  my $lc_fpack;

  $this = shift(@_);

  $lc_pack = shift(@_);

  if ( !defined($lc_pack) || ref($lc_pack) )
  {
    return undef;
  }

  # Construct the fully qualified package name and delegate
  # the actual loading to from_pl_all.
  $lc_fpack = __PACKAGE__ . '::' . $lc_pack;

  return $this->from_pl_all($lc_fpack, @_);
}


sub from_pl_all {
  # Load an ordinary Perl module by its fully qualified package
  # name through @INC.
  #
  # Perl's own %INC registry prevents duplicate module loading.
  # Loading failures return undef, but constructor exceptions
  # remain the responsibility of the plug-in.

  my $this;
  my $lc_package;
  my $lc_loaded;

  $this = shift(@_);

  if ( !$initialized ) { return undef; }

  # Obtain the requested package name.
  $lc_package = shift(@_);

  if ( !defined($lc_package) || ref($lc_package) )
  {
    return undef;
  }

  # Validate the name before incorporating it into dynamically
  # evaluated Perl code.
  if ( $lc_package !~ /\A[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*\z/ )
  {
    return undef;
  }

  # Use Perl's normal require mechanism so that previously
  # loaded modules are not loaded again.
  $lc_loaded = eval("require $lc_package; 1;");

  if ( !$lc_loaded ) { return undef; }

  # Invoke the constructor outside eval, giving it the
  # bartender callback followed by the caller's arguments.
  return $lc_package->new($this, @_);
}


sub fsplug {
  # Construct an object from an external plug-in file, or
  # construct another instance of an existing object's class.
  #
  # Canonical filenames identify previously loaded external
  # plug-ins in the class-wide registry.
  #
  # Failed evaluations consume their assigned package numbers,
  # but are never registered, allowing subsequent retries.
  #
  # Constructor exceptions are intentionally not intercepted.

  my $this;
  my $lc_rawf; # Raw filename
  my $lc_modu; # Module name

  $this = shift(@_);
  $lc_rawf = shift(@_);
  $lc_modu = $this->fscplug($lc_rawf);
  
  # Now return if the loading failed:
  if ( !defined($lc_modu) ) { return undef; }
  return ( $lc_modu->new($this,@_) );
}



sub fscplug {
  # Load an external plug-in file and return its generated package
  # name without constructing an object.
  #
  # Existing blessed objects can also identify their own classes.
  # Canonical filenames share the same package registry as fsplug(),
  # so neither method evaluates a successfully loaded file twice.
  #
  # Failed evaluations consume assigned package numbers but are not
  # registered, allowing the file to be corrected and loaded again.

  my $this;
  my $lc_plugin;
  my $lc_package;
  my $lc_filename; # Name of file being loaded
  my $lc_line_filename; # Version used in the line directive
  my $lc_fh;
  my $lc_source;
  my $lc_code;
  my $lc_load_error;
  my $lc_dirname;
  my $lc_visname; # Legibility add-on to package name

  $this = shift(@_);

  if ( !$initialized ) { return undef; }
  $lc_visname = undef;

  $lc_plugin = shift(@_);

  if ( !defined($lc_plugin) ) { return undef; }
  
  # Just in case a visibility add-on was provided,
  # get it.
  if ( ( ref($lc_plugin) eq 'ARRAY' ) && ( !blessed($lc_plugin) ) )
  {
    my $lc2_a;
    $lc2_a = $lc_plugin;
    ($lc_plugin,$lc_visname) = @$lc2_a;
    if ( defined($lc_visname) && ( $lc_visname !~ /\A[A-Za-z0-9_]+(?:::[A-Za-z0-9_]+)*\z/ ) ) { $lc_visname = undef; }
  }

  # A blessed object already identifies a loaded class, without
  # requiring a constructor call or any file processing.
  $lc_package = blessed($lc_plugin);

  if ( defined($lc_package) )
  {
    return $lc_package;
  }

  # Other references are not valid filenames.
  if ( ref($lc_plugin) ) { return undef; }

  # Resolve relative paths and symbolic links to the same
  # canonical filename used by fsplug().
  $lc_filename = abs_path($lc_plugin);

  if ( !defined($lc_filename) || !-f $lc_filename )
  {
    return undef;
  }

  # If the file is already registered, return its package name
  # without evaluating the source again.
  if ( exists($external_packages{$lc_filename}) )
  {
    return $external_packages{$lc_filename};
  }

  # Read the entire source file before attempting compilation.
  if ( !open($lc_fh, '<:raw', $lc_filename) )
  {
    return undef;
  }

  {
    local $/;
    $lc_source = <$lc_fh>;
  }

  if ( !close($lc_fh) || !defined($lc_source) )
  {
    return undef;
  }

  # Allocate a new package before evaluation, so a failed eval
  # cannot lead to a reused, partially populated namespace.
  $lc_package = $external_namespace . '::a_' . $next_external_number . '_z';
  if ( defined($lc_visname) )
  {
    $lc_package .= ( '::' . $lc_visname );
  }

  $next_external_number = int($next_external_number + 1.2);

  # Make the original filename available to the plug-in.
  $lc_dirname = dirname($lc_filename);
  {
    no strict 'refs';
    ${"${lc_package}::PLUGIN_FILENAME"} = $lc_filename;
    ${"${lc_package}::PLUGIN_DIRNAME"} = $lc_dirname;
    ${"${lc_package}::PLUGINS_BAR"} = $this;
  }

  # Use the original filename when safe; otherwise encode it.
  # Never modify the original $lc_filename.
  $lc_line_filename = $lc_filename;

  if ( $lc_line_filename =~ /["\x00-\x1F\x7F]/ )
  {
    $lc_line_filename = unpack('H*', $lc_filename);
  }

  # Preserve original source line numbers in both cases.
  $lc_code = 'package ' . $lc_package . ";\n"
           . '#line 1 "' . $lc_line_filename . '"' . "\n"
           . $lc_source;

  # Preserve fsplug()'s evaluation behavior, including a source's
  # own choice of strictness and warnings; check $@ instead of
  # the eval's return value, which need not be true.
  {
    no strict;
    no warnings;

    eval($lc_code);
    $lc_load_error = $@;
  }

  if ( $lc_load_error ne '' )
  {
    warn $lc_load_error;
    return undef;
  }

  # Only successful compilation enters the shared registry.
  $external_packages{$lc_filename} = $lc_package;

  return $lc_package;
}


sub ourcls {
  # Load a class from the Pl_MIDI_Gen namespace without
  # constructing an object.
  #
  # The argument is a package name relative to Pl_MIDI_Gen.
  # Return the fully qualified class name on success, or
  # undef if validation or loading fails.
  #
  # Perl's require mechanism uses %INC to avoid loading
  # the same module more than once.

  my $this;
  my $lc_pack;
  my $lc_fpack;
  my $lc_loaded;

  $this = shift(@_);

  if ( !$initialized ) { return undef; }
  if ( scalar(@_) != 1 ) { return undef; }

  $lc_pack = shift(@_);

  if ( !defined($lc_pack) || ref($lc_pack) )
  {
    return undef;
  }

  # Construct the fully qualified class name.
  $lc_fpack = __PACKAGE__ . '::' . $lc_pack;

  # Validate the name before using it in an eval string.
  if ( $lc_fpack !~ /\A[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*\z/ )
  {
    return undef;
  }

  # Load the module without invoking its constructor.
  $lc_loaded = eval("require $lc_fpack; 1;");

  if ( !$lc_loaded ) { return undef; }

  return $lc_fpack;
}


sub note_to_pitch
{
  # Convert a named note and octave into the number of semitones
  # relative to middle C (C4 = 0).
  #
  # Examples: F#3 => -6; Bb3 => -2; C4 => 0; E4 => 4.
  # Return undef when the note spelling is not recognized.

  my $this;
  my $lc_note;
  my $lc_letter;
  my $lc_accidental;
  my $lc_octave;
  my $lc_pitch;
  my %lc_notes;

  $this = shift(@_);
  $lc_note = shift(@_);

  if ( !defined($lc_note) || ref($lc_note) ) { return undef; }
  if ( $lc_note !~ /\A([A-Ga-g])([#b]?)(-?\d+)\z/ )
  {
    return undef;
  }

  $lc_letter = uc($1);
  $lc_accidental = $2;
  $lc_octave = $3;

  %lc_notes = (
    'C' => 0,
    'D' => 2,
    'E' => 4,
    'F' => 5,
    'G' => 7,
    'A' => 9,
    'B' => 11,
  );

  $lc_pitch = $lc_notes{$lc_letter} + (12 * ($lc_octave - 4));

  if ( $lc_accidental eq '#' ) { $lc_pitch += 1; }
  if ( $lc_accidental eq 'b' ) { $lc_pitch -= 1; }

  return $lc_pitch;
}



sub save_file
{
  # Save a binary scalar to a file, overwriting if necessary.
  # Return a hashref with 'ok' indicating success or failure.
  # The containing directory must already exist.

  my $this;
  my $lc_data;
  my $lc_filename;
  my $lc_fh;
  my $lc_written;
  my $lc_closed;

  # Retrieve the object reference and the two arguments.
  $this = shift(@_);
  $lc_data = shift(@_);
  $lc_filename = shift(@_);

  # We cannot write undefined data.
  if ( !defined($lc_data) ) { return { 'ok' => 0 }; }

  # Open the destination for raw binary output.
  # This also overwrites any existing file.
  if ( !open($lc_fh, '>:raw', $lc_filename) ) { return { 'ok' => 0 }; }

  # Write the data, then close the file.
  # Check both operations for errors.
  $lc_written = print {$lc_fh} $lc_data;
  $lc_closed = close($lc_fh);

  # Report failure if either operation failed.
  if ( !$lc_written || !$lc_closed ) { return { 'ok' => 0 }; }

  # Otherwise, the operation succeeded.
  return { 'ok' => 1 };
}


sub fromcls
{
  # Construct a new object using either a package name
  # or an existing object that identifies the class.
  #
  # The class must already be loaded.
  # Constructor arguments receive the bartender first.
  # Return undef for undefined input or uninitialized bartender.

  my $this;
  my $lc_source;
  my $lc_package;

  $this = shift(@_);

  if ( !$initialized ) { return undef; }

  $lc_source = shift(@_);

  if ( !defined($lc_source) ) { return undef; }

  # Determine whether we have an existing object.
  $lc_package = blessed($lc_source);

  if ( !defined($lc_package) )
  {
    # Reject references that are not blessed objects.
    if ( ref($lc_source) ) { return undef; }

    $lc_package = $lc_source;
  }

  # Construct a fresh instance of the identified class.
  return $lc_package->new($this,@_);
}


1;
