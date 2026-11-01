package Pl_MIDI_Gen::Util::Pitch;

use strict;
use warnings;

sub new
{
  # Construct a pitch-conversion utility through the bartender.
  # No engine or instrument state is required.

  my $this;
  my $lc_bartender;

  $this = shift(@_);
  $lc_bartender = shift(@_);

  if ( !defined($lc_bartender) || !ref($lc_bartender) )
  {
    return undef;
  }

  return bless({}, __PACKAGE__);
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

1;

