package Pl_MIDI_Gen::Impl::MIDI1_SingleChan;

use strict;
use warnings;

# Standard MIDI File format 1, one track,
# configurable ticks per quarter note (280 default).
# All voices share MIDI channel 1 (status-byte
# channel index zero).
# Selected voice pitches are integral;
# only the global bend can change
# the sounding pitches without
# retriggering their MIDI notes.

sub capabilities
{
  # Report properties of this implementation, regardless of constructor
  # options; undef for max_voices means no fixed voice-count ceiling.

  my $this;

  $this = shift(@_);

  return {
    'max_voices'       => undef,
    'fractional_pitch' => 0,
    'continuous_pitch' => 0,
    'ind_same_pitch'   => 0,
    'global_bend'      => 1,
    'extension'        => 'midi',
  };
}

sub _number
{
  # Recognize finite numeric scalars without accepting references,
  # infinity, or NaN, which could corrupt the MIDI event stream.

  my $lc_value;

  $lc_value = shift(@_);

  if ( !defined($lc_value) || ref($lc_value) ) { return 0; }
  if ( $lc_value !~ /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/ )
  {
    return 0;
  }

  return 1;
}

sub _round
{
  # Round to the nearest integer, resolving exact half-integer
  # values away from zero as required by the interface.

  my $lc_value;

  $lc_value = shift(@_);

  if ( $lc_value < 0 ) { return int($lc_value - 0.5); }
  return int($lc_value + 0.5);
}

sub _voice
{
  # Resolve a one-based voice number without assuming any maximum
  # beyond the number requested when this object was constructed.

  my $this;
  my $lc_index;

  $this = shift(@_);
  $lc_index = shift(@_);

  if ( !_number($lc_index) || $lc_index !~ /\A[0-9]+\z/ )
  {
    return undef;
  }
  if ( $lc_index < 1 || $lc_index > scalar(@{$this->{'voices'}}) )
  {
    return undef;
  }

  return $this->{'voices'}->[$lc_index - 1];
}

sub _emit
{
  # Record a complete MIDI event at the current absolute tick;
  # events at the same tick retain their order of invocation.

  my $this;
  my $lc_bytes;

  $this = shift(@_);
  $lc_bytes = shift(@_);

  push(@{$this->{'events'}}, [$this->{'tick'}, $lc_bytes]);
  return;
}

sub _send_global_bend
{
  # Translate the current global offset into a channel-one, 14-bit
  # pitch-bend value, using independent upward/downward ranges.

  my $this;
  my $lc_offset;
  my $lc_amount;

  $this = shift(@_);

  if ( !$this->{'global_enabled'} ) { return; }

  $lc_offset = $this->{'global_offset'};
  $lc_amount = 8192;

  if ( $lc_offset > 0 && $this->{'gbend_up'} > 0 )
  {
    $lc_amount = int(8192 + 8191 * $lc_offset / $this->{'gbend_up'} + 0.5);
  } elsif ( $lc_offset < 0 && $this->{'gbend_down'} > 0 ) {
    $lc_amount = int(8192 + 8192 * $lc_offset / $this->{'gbend_down'} + 0.5);
  }

  if ( $lc_amount < 0 ) { $lc_amount = 0; }
  if ( $lc_amount > 16383 ) { $lc_amount = 16383; }

  $this->_emit(pack('C3', 0xE0, ($lc_amount & 127), ($lc_amount >> 7)));
  return;
}

sub _stop
{
  # Stop one logical voice, but keep its MIDI note sounding while
  # another voice is still using the same channel-one pitch.
  # This is shared-note handling, NOT independent same-pitch control.

  my $this;
  my $lc_voice;
  my $lc_pitch;
  my $lc_midi;

  $this = shift(@_);
  $lc_voice = shift(@_);

  if ( !defined($lc_voice->{'on'}) ) { return undef; }

  $lc_pitch = $lc_voice->{'on'};
  $lc_midi = $lc_pitch + 60;

  $this->{'active'}->{$lc_midi} = int($this->{'active'}->{$lc_midi} - 1);

  if ( $this->{'active'}->{$lc_midi} == 0 )
  {
    $this->_emit(pack('C3', 0x80, $lc_midi, 0));
    delete($this->{'active'}->{$lc_midi});
  }

  $lc_voice->{'on'} = undef;
  return $lc_pitch;
}

sub _vlq
{
  # Encode one nonnegative MIDI delta time as a variable-length quantity.

  my $lc_value;
  my $lc_bytes;

  $lc_value = shift(@_);
  $lc_bytes = pack('C', ($lc_value & 127));
  $lc_value = int($lc_value / 128);

  while ( $lc_value > 0 )
  {
    $lc_bytes = pack('C', (($lc_value & 127) | 128)) . $lc_bytes;
    $lc_value = int($lc_value / 128);
  }

  return $lc_bytes;
}

sub new
{
  # Construct any positive number of logical voices with integer
  # selected pitches; ignore individual-voice bend constructor options.
  # Global bending is enabled only when both global ranges are given.

  my $this;
  my $lc_bartender;
  my $lc_pitches;
  my $lc_options;
  my $lc_tpb;
  my $lc_global_enabled;
  my $lc_up;
  my $lc_down;
  my $lc_partial;
  my $lc_pitch;
  my $lc_input;
  my @lc_voices;

  $this = shift(@_);
  $lc_bartender = shift(@_);
  $lc_pitches = shift(@_);
  $lc_options = shift(@_);

  if ( ref($lc_pitches) ne 'ARRAY' || ref($lc_options) ne 'HASH' )
  {
    return undef;
  }
  if ( !@$lc_pitches ) { return undef; }
  if ( exists($lc_options->{'engopt'}) &&
       ref($lc_options->{'engopt'}) ne 'HASH' )
  {
    return undef;
  }

  # Use the framework's default resolution unless the
  # caller supplies a valid override.
  $lc_tpb = 480;

  if ( exists($lc_options->{'tpb'}) )
  {
    $lc_tpb = $lc_options->{'tpb'};

    if ( !_number($lc_tpb) ||
         $lc_tpb !~ /\A[0-9]+\z/ ||
         $lc_tpb < 1 || $lc_tpb > 32767 )
    {
      return undef;
    }
  }

  $lc_global_enabled = 0;
  $lc_up = 0;
  $lc_down = 0;
  $lc_partial = 1;

  if ( exists($lc_options->{'gbend_up'}) &&
       exists($lc_options->{'gbend_down'}) )
  {
    $lc_up = $lc_options->{'gbend_up'};
    $lc_down = $lc_options->{'gbend_down'};

    if ( !_number($lc_up) || !_number($lc_down) ||
         $lc_up < 0 || $lc_down < 0 ||
         $lc_up > 127 || $lc_down > 127 )
    {
      return undef;
    }

    $lc_global_enabled = 1;
  }

  if ( $lc_global_enabled && exists($lc_options->{'gbend_prt'}) )
  {
    $lc_partial = $lc_options->{'gbend_prt'};

    if ( !_number($lc_partial) ||
         ($lc_partial != 0 && $lc_partial != 1) )
    {
      return undef;
    }
  }

  @lc_voices = ();

  foreach $lc_input (@$lc_pitches)
  {
    if ( !_number($lc_input) || $lc_input < -60 || $lc_input > 67 )
    {
      return undef;
    }

    $lc_pitch = _round($lc_input);
    push(@lc_voices, { 'set' => $lc_pitch, 'on' => undef });
  }

  $this = bless({
    'bartender'      => $lc_bartender,
    'tick'           => 0,
    'tpb'            => $lc_tpb,
    'events'         => [],
    'voices'         => \@lc_voices,
    'active'         => {},
    'global_enabled' => $lc_global_enabled,
    'global_offset'  => 0,
    'gbend_up'       => $lc_up,
    'gbend_down'     => $lc_down,
    'gbend_prt'      => $lc_partial,
  }, __PACKAGE__);

  # The segment starts with a defined bend state, independent of
  # whichever MIDI file was played immediately before this one.
  $this->_send_global_bend();

  return $this;
}

sub ticks_forward
{
  # Move monotonically through musical time, or just query it when
  # the optional argument is missing or explicitly zero.

  my $this;
  my $lc_delta;

  $this = shift(@_);
  $lc_delta = shift(@_);

  if ( !defined($lc_delta) ) { $lc_delta = 0; }
  if ( !_number($lc_delta) || $lc_delta !~ /\A[0-9]+\z/ )
  {
    return undef;
  }

  $this->{'tick'} = int($this->{'tick'} + $lc_delta);
  return $this->{'tick'};
}

sub set_pitch
{
  # Select an integral pitch for one voice; do not change an already
  # sounding note because independent continuous bending is absent.

  my $this;
  my $lc_number;
  my $lc_wanted;
  my $lc_voice;
  my $lc_result;

  $this = shift(@_);
  $lc_number = shift(@_);
  $lc_wanted = shift(@_);
  $lc_voice = $this->_voice($lc_number);

  if ( !defined($lc_voice) || !_number($lc_wanted) ||
       $lc_wanted < -60 || $lc_wanted > 67 )
  {
    return {};
  }

  $lc_voice->{'set'} = _round($lc_wanted);
  $lc_result = { 'set' => $lc_voice->{'set'} };

  if ( defined($lc_voice->{'on'}) )
  {
    $lc_result->{'on'} = $lc_voice->{'on'};
  }

  return $lc_result;
}

sub global
{
  # Query or set the shared global pitch offset without changing the
  # selected, reference, or reported sounding pitches of any voice.
  # Unavailable global bending returns a fresh empty hashref.

  my $this;
  my $lc_was;
  my $lc_wanted;
  my $lc_now;

  $this = shift(@_);

  if ( !$this->{'global_enabled'} ) { return {}; }

  $lc_was = $this->{'global_offset'};
  $lc_now = $lc_was;

  if ( scalar(@_) > 0 )
  {
    $lc_wanted = shift(@_);
    if ( !_number($lc_wanted) ) { return {}; }

    if ( $lc_wanted >= -$this->{'gbend_down'} &&
         $lc_wanted <= $this->{'gbend_up'} )
    {
      $lc_now = $lc_wanted;
    } elsif ( $this->{'gbend_prt'} ) {
      if ( $lc_wanted > $this->{'gbend_up'} )
      {
        $lc_now = $this->{'gbend_up'};
      } else {
        $lc_now = -$this->{'gbend_down'};
      }
    }

    if ( $lc_now != $lc_was )
    {
      $this->{'global_offset'} = $lc_now;
      $this->_send_global_bend();
    }
  }

  return { 'was' => $lc_was, 'now' => $lc_now };
}

sub note_on
{
  # Replace a sounding note on this voice, then start its selected
  # integer pitch; return all three required initial-note values.
  # Simultaneous equal pitches share a note, not independent attacks.

  my $this;
  my $lc_number;
  my $lc_options;
  my $lc_voice;
  my $lc_velocity;
  my $lc_pitch;
  my $lc_midi;

  $this = shift(@_);
  $lc_number = shift(@_);
  $lc_options = shift(@_);
  $lc_voice = $this->_voice($lc_number);

  if ( !defined($lc_voice) || ref($lc_options) ne 'HASH' )
  {
    return {};
  }

  $lc_velocity = $lc_options->{'vel'};
  if ( !_number($lc_velocity) || $lc_velocity !~ /\A[0-9]+\z/ ||
       $lc_velocity < 1 || $lc_velocity > 127 )
  {
    return {};
  }

  $lc_pitch = $lc_voice->{'set'};
  $lc_midi = $lc_pitch + 60;

  # Validate before stopping the previously sounding voice.
  if ( $lc_midi < 0 || $lc_midi > 127 ) { return {}; }

  $this->_stop($lc_voice);

  if ( !exists($this->{'active'}->{$lc_midi}) )
  {
    $this->_emit(pack('C3', 0x90, $lc_midi, $lc_velocity));
    $this->{'active'}->{$lc_midi} = 0;
  }

  $this->{'active'}->{$lc_midi} = int($this->{'active'}->{$lc_midi} + 1.2);
  $lc_voice->{'on'} = $lc_pitch;

  return { 'on' => $lc_pitch, 'ref' => $lc_pitch, 'bend' => 0 };
}

sub note_off
{
  # Stop a logical voice, returning its unbent pitch, or undef
  # if that voice was already silent.

  my $this;
  my $lc_number;
  my $lc_voice;

  $this = shift(@_);
  $lc_number = shift(@_);
  $lc_voice = $this->_voice($lc_number);

  if ( !defined($lc_voice) ) { return undef; }
  return $this->_stop($lc_voice);
}

sub end
{
  # Close the current SMF format-1 segment and return its bytes.
  # Clear its event history and reset time, but retain selected
  # voice pitches and the current global pitch offset.

  my $this;
  my $lc_voice;
  my $lc_event;
  my $lc_delta;
  my $lc_previous;
  my $lc_track;
  my $lc_header;
  my $lc_result;

  $this = shift(@_);

  foreach $lc_voice (@{$this->{'voices'}})
  {
    $this->_stop($lc_voice);
  }

  $this->_emit("\xFF\x2F\x00");
  $lc_previous = 0;
  $lc_track = '';

  foreach $lc_event (@{$this->{'events'}})
  {
    $lc_delta = $lc_event->[0] - $lc_previous;

    # MIDI variable-length time values cannot exceed 28 bits.
    # Split any longer silent interval with inert meta events.
    while ( $lc_delta > 0x0FFFFFFF )
    {
      $lc_track .= _vlq(0x0FFFFFFF) . "\xFF\x7F\x00";
      $lc_delta -= 0x0FFFFFFF;
    }

    $lc_track .= _vlq($lc_delta) . $lc_event->[1];
    $lc_previous = $lc_event->[0];
  }

  $lc_header = 'MThd' . pack('Nnnn', 6, 1, 1, $this->{'tpb'});
  $lc_result = $lc_header . 'MTrk' . pack('N', length($lc_track)) . $lc_track;

  $this->{'tick'} = 0;
  $this->{'events'} = [];
  $this->{'active'} = {};

  # The next segment will establish the preserved offset at tick 0,
  # regardless of whether or when its first note starts sounding.
  $this->_send_global_bend();

  return $lc_result;
}

1;


