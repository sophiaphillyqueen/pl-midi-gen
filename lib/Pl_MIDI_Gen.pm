package Pl_MIDI_Gen;

use strict;
use warnings;

use Cwd qw(abs_path);
use Scalar::Util qw(blessed);

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

  return bless( {}, __PACKAGE__ );
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
  my $lc_plugin;
  my $lc_package;
  my $lc_filename;
  my $lc_fh;
  my $lc_source;
  my $lc_code;
  my $lc_load_error;

  $this = shift(@_);

  if ( !$initialized ) { return undef; }

  $lc_plugin = shift(@_);

  if ( !defined($lc_plugin) ) { return undef; }

  # First determine whether the caller supplied an existing
  # blessed object rather than a filename.
  #
  # Such an object already identifies a loaded package, so
  # no filename resolution or registry lookup is needed.
  $lc_package = blessed($lc_plugin);

  if ( defined($lc_package) )
  {
    return $lc_package->new($this, @_);
  }

  # Other references are not valid filenames.
  if ( ref($lc_plugin) ) { return undef; }

  # Resolve the supplied filename into its canonical form,
  # accounting for relative paths and symbolic links.
  $lc_filename = abs_path($lc_plugin);

  if ( !defined($lc_filename) || !-f $lc_filename )
  {
    return undef;
  }

  # If this file was loaded previously, use its registered
  # package without executing its source again.
  if ( exists($external_packages{$lc_filename}) )
  {
    $lc_package = $external_packages{$lc_filename};

    return $lc_package->new($this, @_);
  }

  # Open the plug-in source file for reading.
  if ( !open($lc_fh, '<:raw', $lc_filename) )
  {
    return undef;
  }

  # Read the entire source file into a single scalar.
  {
    local $/;
    $lc_source = <$lc_fh>;
  }

  if ( !close($lc_fh) || !defined($lc_source) )
  {
    return undef;
  }

  # Assign the next package name.
  #
  # Increment the counter before compilation so that a
  # failed attempt cannot reuse a potentially contaminated
  # package namespace.
  $lc_package = $external_namespace . '::a_' . $next_external_number . '_z';

  $next_external_number = int($next_external_number + 1.2);

  # External plug-ins must not contain their own package
  # declarations.
  #
  # Prepend our generated package declaration to the code.
  $lc_code = 'package ' . $lc_package . ";\n" . $lc_source;

  # Evaluate the assembled Perl source.
  #
  # Do not impose this module's lexical strictness or warning
  # settings on the external source; the plug-in may establish
  # its own settings.
  #
  # Capture the evaluation error immediately.
  {
    no strict;
    no warnings;

    eval($lc_code);
    $lc_load_error = $@;
  }

  # A successful evaluation need not return a true value,
  # so use the evaluation error rather than its return value.
  if ( $lc_load_error ne '' ) { return undef; }

  # The source loaded successfully, so record its package
  # against the canonical filename.
  $external_packages{$lc_filename} = $lc_package;

  # Finally, construct the plug-in object outside eval.
  # Any exception here belongs to the plug-in itself.
  return $lc_package->new($this, @_);
}


1;