package Pl_MIDI_Gen::Impl::MIDI1_MultiChan;

use strict;
use warnings;

# Standard MIDI File format 1, one track, 480 ticks per quarter note
# MIDI channel 1 is reserved; voices 1 through 15 use channels 2 through 16

sub capabilities {
  # Report implementation capabilities without exposing internal state

  my $this;

  $this = shift(@_);

  return {
    'max_voices'       => 15,
    'fractional_pitch' => 1,
    'continuous_pitch' => 1,
    'ind_same_pitch'   => 1,
    'extension'        => 'midi',
  };
}


sub _number {
  # Accept ordinary finite decimal numbers, but not references or NaN

  my $lc_value;

  $lc_value = shift(@_);

  if ( !defined($lc_value) || ref($lc_value) ) { return 0; }
  if ( $lc_value !~ /\A[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?\z/ )
  {
    return 0;
  }

  return 1;
}


sub _round {
  # Round a semitone value to the nearest integer, away from zero at ties

  my $lc_value;

  $lc_value = shift(@_);

  if ( $lc_value < 0 ) { return int($lc_value - 0.5); }
  return int($lc_value + 0.5);
}


sub _voice {
  # Find one of the engine's one-based voices, if its index is valid

  my $this;
  my $lc_index;

  $this = shift(@_);
  $lc_index = shift(@_);

  if ( !_number($lc_index) ) { return undef; }
  if ( $lc_index !~ /\A\d+\z/ ) { return undef; }
  if ( $lc_index < 1 || $lc_index > scalar(@{$this->{'voices'}}) )
  {
    return undef;
  }

  return $this->{'voices'}->[$lc_index - 1];
}


sub _reference {
  # Choose the closest MIDI note capable of reaching a selected pitch
  # When both adjacent MIDI notes cannot reach it, use the closest note

  my $this;
  my $lc_pitch;
  my $lc_abs;
  my $lc_floor;
  my $lc_ceil;
  my $lc_nearest;
  my $lc_other;
  my $lc_delta;

  $this = shift(@_);
  $lc_pitch = shift(@_);
  $lc_abs = $lc_pitch + 60;
  $lc_floor = int($lc_abs);
  $lc_ceil = $lc_floor;

  if ( $lc_abs != $lc_floor )
  {
    $lc_ceil = int($lc_floor + 1.2);
  }

  $lc_nearest = _round($lc_abs);
  $lc_other = $lc_floor;
  if ( $lc_nearest == $lc_floor ) { $lc_other = $lc_ceil; }

  # Prefer the nearest anchor, provided its bend is reachable
  $lc_delta = $lc_abs - $lc_nearest;
  if ( $lc_nearest >= 0 && $lc_nearest <= 127 &&
       $lc_delta <= $this->{'bend_up'} &&
       $lc_delta >= -$this->{'bend_down'} )
  {
    return $lc_nearest;
  }

  # Asymmetric ranges can make the opposite neighbor preferable
  $lc_delta = $lc_abs - $lc_other;
  if ( $lc_other >= 0 && $lc_other <= 127 &&
       $lc_delta <= $this->{'bend_up'} &&
       $lc_delta >= -$this->{'bend_down'} )
  {
    return $lc_other;
  }

  return undef;
}


sub _selected_pitch {
  # Round only when bending is disabled or cannot reproduce this fraction

  my $this;
  my $lc_pitch;
  my $lc_nearest;

  $this = shift(@_);
  $lc_pitch = shift(@_);

  if ( !$this->{'bending'} || $lc_pitch == _round($lc_pitch) )
  {
    return _round($lc_pitch);
  }

  $lc_nearest = $this->_reference($lc_pitch);
  if ( !defined($lc_nearest) ) { return _round($lc_pitch); }

  return $lc_pitch;
}


sub _emit {
  # Record a MIDI event at the current absolute musical tick

  my $this;
  my $lc_bytes;

  $this = shift(@_);
  $lc_bytes = shift(@_);

  push(@{$this->{'events'}}, [$this->{'tick'}, $lc_bytes]);
  return;
}


sub _bend {
  # Convert a target pitch to a MIDI 14-bit pitch-bend message
  # Use separate upward and downward ranges, matching instrument settings

  my $this;
  my $lc_voice;
  my $lc_pitch;
  my $lc_delta;
  my $lc_amount;
  my $lc_status;

  $this = shift(@_);
  $lc_voice = shift(@_);
  $lc_pitch = shift(@_);

  if ( !$this->{'bending'} ) { return; }

  $lc_delta = $lc_pitch + 60 - $lc_voice->{'reference'};
  $lc_amount = 8192;

  if ( $lc_delta > 0 && $this->{'bend_up'} > 0 )
  {
    $lc_amount = int(8192 + (8191 * $lc_delta / $this->{'bend_up'}) + 0.5);
  }
  if ( $lc_delta < 0 && $this->{'bend_down'} > 0 )
  {
    $lc_amount = int(8192 + (8192 * $lc_delta / $this->{'bend_down'}) + 0.5);
  }

  if ( $lc_amount < 0 ) { $lc_amount = 0; }
  if ( $lc_amount > 16383 ) { $lc_amount = 16383; }

  # Emit on the first use of a channel or whenever its bend changes
  if ( !$lc_voice->{'bend_sent'} || $lc_voice->{'bend_value'} != $lc_amount )
  {
    $lc_status = 0xE0 | $lc_voice->{'channel'};
    $this->_emit(pack('C3', $lc_status, ($lc_amount & 127), ($lc_amount >> 7)));
    $lc_voice->{'bend_value'} = $lc_amount;
    $lc_voice->{'bend_sent'} = 1;
  }

  return;
}


sub _stop {
  # End an active note, remembering its actual sounding pitch
  # A silent voice remains unchanged

  my $this;
  my $lc_voice;
  my $lc_pitch;
  my $lc_status;

  $this = shift(@_);
  $lc_voice = shift(@_);

  if ( !defined($lc_voice->{'on'}) ) { return undef; }

  $lc_pitch = $lc_voice->{'on'};
  $lc_status = 0x80 | $lc_voice->{'channel'};
  $this->_emit(pack('C3', $lc_status, $lc_voice->{'reference'}, 0));

  $lc_voice->{'on'} = undef;
  $lc_voice->{'reference'} = undef;

  # Silence first, then restore the channel's neutral bend
  if ( $this->{'bending'} && $lc_voice->{'bend_value'} != 8192 )
  {
    $lc_status = 0xE0 | $lc_voice->{'channel'};
    $this->_emit(pack('C3', $lc_status, 0, 64));
    $lc_voice->{'bend_value'} = 8192;
    $lc_voice->{'bend_sent'} = 1;
  }

  return $lc_pitch;
}


sub _vlq {
  # Encode a nonnegative MIDI delta time in variable-length form

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


sub new {
  # Construct independent voices with their initial selected pitches
  # Bend ranges are optional but both are needed for fractional pitches

  my $this;
  my $lc_bartender;
  my $lc_pitches;
  my $lc_options;
  my $lc_bending;
  my $lc_bend_up;
  my $lc_bend_down;
  my $lc_bend_prt;
  my $lc_pitch;
  my $lc_input_pitch;
  my $lc_voice;
  my $lc_index;
  my @lc_voices;

  $this = shift(@_);
  $lc_bartender = shift(@_);
  $lc_pitches = shift(@_);
  $lc_options = shift(@_);

  if ( ref($lc_pitches) ne 'ARRAY' ) { return undef; }
  if ( ref($lc_options) ne 'HASH' ) { return undef; }
  if ( scalar(@$lc_pitches) < 1 || scalar(@$lc_pitches) > 15 )
  {
    return undef;
  }
  if ( exists($lc_options->{'engopt'}) &&
       ref($lc_options->{'engopt'}) ne 'HASH' )
  {
    return undef;
  }

  $lc_bending = 0;
  $lc_bend_up = 0;
  $lc_bend_down = 0;

  if ( exists($lc_options->{'bend_up'}) && exists($lc_options->{'bend_down'}) )
  {
    $lc_bend_up = $lc_options->{'bend_up'};
    $lc_bend_down = $lc_options->{'bend_down'};

    if ( !_number($lc_bend_up) || !_number($lc_bend_down) )
    {
      return undef;
    }
    if ( $lc_bend_up < 0 || $lc_bend_down < 0 ||
         $lc_bend_up > 127 || $lc_bend_down > 127 )
    {
      return undef;
    }

    if ( $lc_bend_up > 0 || $lc_bend_down > 0 )
    {
      $lc_bending = 1;
    }
  }

  $lc_bend_prt = 1;
  if ( $lc_bending && exists($lc_options->{'bend_prt'}) )
  {
    $lc_bend_prt = $lc_options->{'bend_prt'};
    if ( !_number($lc_bend_prt) ||
         ( $lc_bend_prt != 0 && $lc_bend_prt != 1 ) )
    {
      return undef;
    }
  }

  $this = bless({
    'bartender'  => $lc_bartender,
    'tick'       => 0,
    'events'     => [],
    'voices'     => [],
    'bending'    => $lc_bending,
    'bend_up'    => $lc_bend_up,
    'bend_down'  => $lc_bend_down,
    'bend_prt'   => $lc_bend_prt,
  }, __PACKAGE__);

  $lc_index = 0;
  foreach $lc_input_pitch (@$lc_pitches)
  {
    $lc_pitch = $lc_input_pitch;
    if ( !_number($lc_pitch) || $lc_pitch < -60 || $lc_pitch > 67 )
    {
      return undef;
    }

    $lc_index = int($lc_index + 1.2);
    $lc_pitch = $this->_selected_pitch($lc_pitch);
    $lc_voice = {
      'channel'    => $lc_index,
      'set'        => $lc_pitch,
      'on'         => undef,
      'reference'  => undef,
      'bend_value' => 8192,
      'bend_sent'  => 0,
    };
    push(@lc_voices, $lc_voice);
  }

  $this->{'voices'} = \@lc_voices;
  return $this;
}


sub ticks_forward {
  # Move forward by an optional nonnegative integral number of MIDI ticks
  # Always return the new current tick, including for a zero-time query

  my $this;
  my $lc_delta;

  $this = shift(@_);
  $lc_delta = shift(@_);

  if ( !defined($lc_delta) ) { $lc_delta = 0; }
  if ( !_number($lc_delta) || $lc_delta !~ /\A\d+\z/ )
  {
    return undef;
  }

  $this->{'tick'} = int($this->{'tick'} + $lc_delta);
  return $this->{'tick'};
}


sub set_pitch {
  # Select the pitch of a voice and optionally bend its active note
  # Return independent 'set' and, when sounding, 'on' values

  my $this;
  my $lc_number;
  my $lc_wanted;
  my $lc_voice;
  my $lc_selected;
  my $lc_delta;
  my $lc_new_on;
  my $lc_result;

  $this = shift(@_);
  $lc_number = shift(@_);
  $lc_wanted = shift(@_);
  $lc_voice = $this->_voice($lc_number);

  if ( !defined($lc_voice) || !_number($lc_wanted) ||
       $lc_wanted < -60 || $lc_wanted > 67 )
  {
    return undef;
  }

  $lc_selected = $this->_selected_pitch($lc_wanted);
  $lc_voice->{'set'} = $lc_selected;

  if ( defined($lc_voice->{'on'}) && $this->{'bending'} )
  {
    $lc_delta = $lc_selected + 60 - $lc_voice->{'reference'};
    $lc_new_on = undef;

    if ( $lc_delta >= -$this->{'bend_down'} &&
         $lc_delta <= $this->{'bend_up'} )
    {
      $lc_new_on = $lc_selected;
    } elsif ( $this->{'bend_prt'} ) {
      if ( $lc_delta > $this->{'bend_up'} )
      {
        $lc_new_on = $lc_voice->{'reference'} - 60 + $this->{'bend_up'};
      } else {
        $lc_new_on = $lc_voice->{'reference'} - 60 - $this->{'bend_down'};
      }
    }

    if ( defined($lc_new_on) )
    {
      $this->_bend($lc_voice, $lc_new_on);
      $lc_voice->{'on'} = $lc_new_on;
    }
  }

  $lc_result = { 'set' => $lc_voice->{'set'} };
  if ( defined($lc_voice->{'on'}) )
  {
    $lc_result->{'on'} = $lc_voice->{'on'};
  }

  return $lc_result;
}


sub note_on {
  # End the previous note, if present, and start a new one on this voice
  # Require a positive MIDI velocity in the caller's options hash

  my $this;
  my $lc_number;
  my $lc_options;
  my $lc_voice;
  my $lc_velocity;
  my $lc_reference;
  my $lc_status;
  my $lc_pitch;

  $this = shift(@_);
  $lc_number = shift(@_);
  $lc_options = shift(@_);
  $lc_voice = $this->_voice($lc_number);

  if ( !defined($lc_voice) || ref($lc_options) ne 'HASH' )
  {
    return undef;
  }

  $lc_velocity = $lc_options->{'vel'};
  if ( !_number($lc_velocity) || $lc_velocity !~ /\A\d+\z/ ||
       $lc_velocity < 1 || $lc_velocity > 127 )
  {
    return undef;
  }

  $lc_pitch = $lc_voice->{'set'};
  $lc_reference = 60 + _round($lc_pitch);
  if ( $this->{'bending'} )
  {
    $lc_reference = $this->_reference($lc_pitch);
  }
  if ( !defined($lc_reference) ) { return undef; }

  # All validation is complete before replacing any active note
  $this->_stop($lc_voice);
  $lc_voice->{'reference'} = $lc_reference;

  if ( $this->{'bending'} )
  {
    $this->_bend($lc_voice, $lc_pitch);
  }

  $lc_status = 0x90 | $lc_voice->{'channel'};
  $this->_emit(pack('C3', $lc_status, $lc_reference, $lc_velocity));
  $lc_voice->{'on'} = $lc_pitch;

  return $lc_pitch;
}


sub note_off {
  # Stop the selected voice and return its former sounding pitch
  # A silent voice returns undef without emitting any event

  my $this;
  my $lc_number;
  my $lc_voice;

  $this = shift(@_);
  $lc_number = shift(@_);
  $lc_voice = $this->_voice($lc_number);

  if ( !defined($lc_voice) ) { return undef; }
  return $this->_stop($lc_voice);
}


sub end {
  # Terminate all active notes and return a complete SMF format-1 file
  # Reset musical time and events, keeping the voices' selected pitches

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

    # Standard MIDI variable-length quantities encode up to 28 bits
    # Quiet sequencer-specific events bridge longer otherwise empty gaps
    while ( $lc_delta > 0x0FFFFFFF )
    {
      $lc_track .= _vlq(0x0FFFFFFF) . "\xFF\x7F\x00";
      $lc_delta -= 0x0FFFFFFF;
    }

    $lc_track .= _vlq($lc_delta) . $lc_event->[1];
    $lc_previous = $lc_event->[0];
  }

  $lc_header = 'MThd' . pack('Nnnn', 6, 1, 1, 480);
  $lc_result = $lc_header . 'MTrk' . pack('N', length($lc_track)) . $lc_track;

  $this->{'tick'} = 0;
  $this->{'events'} = [];
  foreach $lc_voice (@{$this->{'voices'}})
  {
    $lc_voice->{'on'} = undef;
    $lc_voice->{'reference'} = undef;
    $lc_voice->{'bend_value'} = 8192;
    $lc_voice->{'bend_sent'} = 0;
  }

  return $lc_result;
}


1;

