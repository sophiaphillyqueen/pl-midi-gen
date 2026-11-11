# Pl_MIDI_Gen::Impl::MIDI1_MultiChan
# Independent MIDI channels per voice.
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

package Pl_MIDI_Gen::Impl::MIDI1_MultiChan;

use strict;
use warnings;

# Standard MIDI File format 1, one track.
# Each of up to 15 voices uses its own pitched channel.
# MIDI channel 10 is reserved for percussion and never
# assigned to a voice.
#
# 480 ticks per quarter note by default; the constructor
# can select another resolution.

sub capabilities
{
  # Return a fresh description of capabilities, regardless
  # of which constructor options enabled individual bending.

  my $this;
  $this = shift(@_);

  return {
    'max_voices'       => 15,
    'fractional_pitch' => 1,
    'continuous_pitch' => 1,
    'ind_same_pitch'   => 1,
    'global_bend'      => 0,
    'extension'        => 'midi',
  };
}


sub _number
{
  # Accept ordinary decimal numbers, but not references,
  # NaN, or infinity.

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
  # Round half-integers away from zero,
  # including negative pitches.

  my $lc_value;
  $lc_value = shift(@_);

  if ( $lc_value < 0 ) { return int($lc_value - 0.5); }
  return int($lc_value + 0.5);
}


sub _voice
{
  # Resolve a valid, one-based voice index
  # to the voice structure.

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


sub _reference
{
  # Choose the closest MIDI note that can reach
  # the selected pitch within the configured
  # individual bend limits.

  my $this;
  my $lc_pitch;
  my $lc_absolute;
  my $lc_floor;
  my $lc_ceil;
  my $lc_nearest;
  my $lc_other;
  my $lc_delta;
  $this = shift(@_);
  $lc_pitch = shift(@_);

  $lc_absolute = $lc_pitch + 60;
  $lc_floor = int($lc_absolute);
  $lc_ceil = $lc_floor;
  if ( $lc_absolute != $lc_floor )
  {
    $lc_ceil = int($lc_floor + 1.2);
  }

  $lc_nearest = _round($lc_absolute);
  $lc_other = $lc_floor;
  if ( $lc_nearest == $lc_floor ) { $lc_other = $lc_ceil; }

  # Prefer the nearest reference if it is reachable.
  $lc_delta = $lc_absolute - $lc_nearest;
  if ( $lc_nearest >= 0 && $lc_nearest <= 127 &&
       $lc_delta >= -$this->{'bend_down'} &&
       $lc_delta <= $this->{'bend_up'} )
  {
    return $lc_nearest;
  }

  # Otherwise, see whether the adjacent reference works.
  $lc_delta = $lc_absolute - $lc_other;
  if ( $lc_other >= 0 && $lc_other <= 127 &&
       $lc_delta >= -$this->{'bend_down'} &&
       $lc_delta <= $this->{'bend_up'} )
  {
    return $lc_other;
  }

  return undef;
}


sub _selected_pitch
{
  # Preserve a fractional selection only when an
  # appropriate MIDI reference note can produce it
  # with the configured bend limits.

  my $this;
  my $lc_pitch;
  $this = shift(@_);
  $lc_pitch = shift(@_);

  if ( !$this->{'bending'} || $lc_pitch == _round($lc_pitch) )
  {
    return _round($lc_pitch);
  }

  if ( !defined($this->_reference($lc_pitch)) )
  {
    return _round($lc_pitch);
  }

  return $lc_pitch;
}


sub _emit
{
  # Record a complete MIDI event at the current tick.
  # Events at the same tick retain their invocation order.

  my $this;
  my $lc_bytes;
  $this = shift(@_);
  $lc_bytes = shift(@_);

  push(@{$this->{'events'}}, [$this->{'tick'}, $lc_bytes]);
  return;
}


sub _bend
{
  # Send the voice's bend, setting its channel's
  # pitch-bend sensitivity through RPN 0,0 before
  # first use in this segment.
  #
  # The sensitivity is symmetric, but software-enforced
  # individual bend limits may differ upward and downward.

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

  # Configure this channel's pitch-bend sensitivity,
  # if it has not yet been configured for this segment.
  if ( !$lc_voice->{'bend_configured'} )
  {
    $lc_status = 0xB0 | $lc_voice->{'channel'};
    $this->_emit(pack('C3',$lc_status,101,0));
    $this->_emit(pack('C3',$lc_status,100,0));
    $this->_emit(pack('C3',$lc_status,6,$this->{'bend_span'}));
    $this->_emit(pack('C3',$lc_status,38,0));
    $this->_emit(pack('C3',$lc_status,101,127));
    $this->_emit(pack('C3',$lc_status,100,127));
    $lc_voice->{'bend_configured'} = 1;
  }

  # Calculate the bend from the established reference.
  $lc_delta = $lc_pitch + 60 - $lc_voice->{'reference'};
  $lc_amount = 8192;

  if ( $lc_delta > 0 )
  {
    $lc_amount = int(
      8192 + 8191 * $lc_delta / $this->{'bend_span'} + 0.5
    );
  } elsif ( $lc_delta < 0 ) {
    $lc_amount = int(
      8192 + 8192 * $lc_delta / $this->{'bend_span'} + 0.5
    );
  }

  # Constrain the result to MIDI's 14-bit range.
  if ( $lc_amount < 0 ) { $lc_amount = 0; }
  if ( $lc_amount > 16383 ) { $lc_amount = 16383; }

  # Send the bend when first using the channel,
  # or when the bend value actually changes.
  if ( !$lc_voice->{'bend_sent'} ||
       $lc_voice->{'bend_value'} != $lc_amount )
  {
    $lc_status = 0xE0 | $lc_voice->{'channel'};
    $this->_emit(pack(
      'C3',
      $lc_status,
      ($lc_amount & 127),
      ($lc_amount >> 7)
    ));

    $lc_voice->{'bend_value'} = $lc_amount;
    $lc_voice->{'bend_sent'} = 1;
  }

  return;
}


sub _stop
{
  # Stop only this voice, not any equal-pitch note
  # sounding on another channel.
  #
  # Silence the note before restoring the channel's
  # centered pitch bend.

  my $this;
  my $lc_voice;
  my $lc_pitch;
  my $lc_status;
  $this = shift(@_);
  $lc_voice = shift(@_);

  if ( !defined($lc_voice->{'on'}) ) { return undef; }

  $lc_pitch = $lc_voice->{'on'};
  $lc_status = 0x80 | $lc_voice->{'channel'};
  $this->_emit(pack('C3',$lc_status,$lc_voice->{'reference'},0));

  $lc_voice->{'on'} = undef;
  $lc_voice->{'reference'} = undef;

  # Restore neutral pitch bend for this channel.
  if ( $this->{'bending'} && $lc_voice->{'bend_value'} != 8192 )
  {
    $lc_status = 0xE0 | $lc_voice->{'channel'};
    $this->_emit(pack('C3',$lc_status,0,64));
    $lc_voice->{'bend_value'} = 8192;
    $lc_voice->{'bend_sent'} = 1;
  }

  return $lc_pitch;
}


sub _vlq
{
  # Encode one nonnegative MIDI delta as
  # variable-length bytes.

  my $lc_value;
  my $lc_bytes;
  $lc_value = shift(@_);

  $lc_bytes = pack('C',($lc_value & 127));
  $lc_value = int($lc_value / 128);

  while ( $lc_value > 0 )
  {
    $lc_bytes = pack('C',(($lc_value & 127) | 128)) . $lc_bytes;
    $lc_value = int($lc_value / 128);
  }

  return $lc_bytes;
}


sub new
{
  # Construct one to fifteen independently addressable voices.
  #
  # Individual pitch bending is enabled only when both
  # bend ranges are supplied.
  #
  # Global bending options have no effect in this implementation.

  my $this;
  my $lc_bartender;
  my $lc_pitches;
  my $lc_options;
  my $lc_tpb;
  my $lc_bending;
  my $lc_up;
  my $lc_down;
  my $lc_partial;
  my $lc_span;
  my $lc_index;
  my $lc_channel;
  my $lc_input;
  my $lc_pitch;
  my @lc_voices;
  $this = shift(@_);
  $lc_bartender = shift(@_);
  $lc_pitches = shift(@_);
  $lc_options = shift(@_);

  # Validate the required constructor structures.
  if ( ref($lc_pitches) ne 'ARRAY' || ref($lc_options) ne 'HASH' )
  {
    return undef;
  }
  if ( !@$lc_pitches || @$lc_pitches > 15 ) { return undef; }
  if ( exists($lc_options->{'engopt'}) &&
       ref($lc_options->{'engopt'}) ne 'HASH' )
  {
    return undef;
  }

  # Validate the ticks-per-beat resolution.
  # Default: 480.
  $lc_tpb = 480;
  if ( exists($lc_options->{'tpb'}) )
  {
    $lc_tpb = $lc_options->{'tpb'};
    if ( !_number($lc_tpb) || $lc_tpb !~ /\A[0-9]+\z/ ||
         $lc_tpb < 1 || $lc_tpb > 32767 )
    {
      return undef;
    }
  }

  # Initially, individual pitch bending is disabled.
  $lc_bending = 0;
  $lc_up = 0;
  $lc_down = 0;
  $lc_partial = 1;
  $lc_span = 0;

  # Enable individual bending only if both limits exist.
  if ( exists($lc_options->{'bend_up'}) &&
       exists($lc_options->{'bend_down'}) )
  {
    $lc_up = $lc_options->{'bend_up'};
    $lc_down = $lc_options->{'bend_down'};

    if ( !_number($lc_up) || !_number($lc_down) ||
         $lc_up < 0 || $lc_down < 0 ||
         $lc_up > 127 || $lc_down > 127 )
    {
      return undef;
    }

    if ( $lc_up > 0 || $lc_down > 0 )
    {
      $lc_bending = 1;

      # MIDI's pitch-bend sensitivity setting is symmetric,
      # so use the larger range for the MIDI channel itself.
      $lc_span = $lc_up;
      if ( $lc_down > $lc_span ) { $lc_span = $lc_down; }

      $lc_span = int($lc_span);
      if ( $lc_span < $lc_up || $lc_span < $lc_down )
      {
        $lc_span = int($lc_span + 1.2);
      }
    }
  }

  # Check the optional policy for unreachable bends.
  if ( $lc_bending && exists($lc_options->{'bend_prt'}) )
  {
    $lc_partial = $lc_options->{'bend_prt'};
    if ( !_number($lc_partial) ||
         ($lc_partial != 0 && $lc_partial != 1) )
    {
      return undef;
    }
  }

  # Establish the engine's internal state.
  $this = bless({
    'bartender'  => $lc_bartender,
    'tick'       => 0,
    'tpb'        => $lc_tpb,
    'events'     => [],
    'voices'     => [],
    'bending'    => $lc_bending,
    'bend_up'    => $lc_up,
    'bend_down'  => $lc_down,
    'bend_prt'   => $lc_partial,
    'bend_span'  => $lc_span,
  }, __PACKAGE__);

  # Set up the independently addressable voices.
  @lc_voices = ();
  $lc_index = 0;

  foreach $lc_input (@$lc_pitches)
  {
    # Starting pitch must be representable by MIDI.
    if ( !_number($lc_input) ||
         $lc_input < -60 || $lc_input > 67 )
    {
      return undef;
    }

    $lc_pitch = $this->_selected_pitch($lc_input);

    # Use MIDI channels 1-9 and 11-16.
    # Channel 10 is reserved for percussion.
    $lc_channel = $lc_index;
    if ( $lc_channel >= 9 )
    {
      $lc_channel = int($lc_channel + 1.2);
    }

    push(@lc_voices, {
      'channel'         => $lc_channel,
      'set'             => $lc_pitch,
      'on'              => undef,
      'reference'       => undef,
      'bend_value'      => 8192,
      'bend_sent'       => 0,
      'bend_configured' => 0,
    });

    $lc_index = int($lc_index + 1.2);
  }

  $this->{'voices'} = \@lc_voices;
  return $this;
}


sub ticks_forward
{
  # Advance the nonnegative musical clock,
  # or query it without moving.

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
  # Select a new pitch without ending the current note.
  #
  # When continuous bending is enabled, attempt to bend
  # the sounding note using its existing reference.
  #
  # Always return a fresh hashref, including on failure.

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

  # An invalid voice returns an empty hash.
  if ( !defined($lc_voice) ) { return {}; }

  # Invalid pitch input leaves the selection unchanged.
  if ( _number($lc_wanted) )
  {
    # Keep selected pitches inside MIDI's available range.
    if ( $lc_wanted < -60 ) { $lc_wanted = -60; }
    if ( $lc_wanted > 67 ) { $lc_wanted = 67; }

    $lc_selected = $this->_selected_pitch($lc_wanted);
    $lc_voice->{'set'} = $lc_selected;

    # An active note may move by pitch bending,
    # but its reference pitch must remain unchanged.
    if ( defined($lc_voice->{'on'}) && $this->{'bending'} )
    {
      $lc_delta = $lc_selected + 60 - $lc_voice->{'reference'};
      $lc_new_on = undef;

      # The requested pitch is reachable.
      if ( $lc_delta >= -$this->{'bend_down'} &&
           $lc_delta <= $this->{'bend_up'} )
      {
        $lc_new_on = $lc_selected;
      } elsif ( $this->{'bend_prt'} ) {
        # The requested pitch is unreachable.
        # When partial bends are allowed, go as far
        # as the appropriate limit permits.
        if ( $lc_delta > $this->{'bend_up'} )
        {
          $lc_new_on =
            $lc_voice->{'reference'} - 60 + $this->{'bend_up'};
        } else {
          $lc_new_on =
            $lc_voice->{'reference'} - 60 - $this->{'bend_down'};
        }
      }

      # Apply a reachable bend, if any.
      if ( defined($lc_new_on) )
      {
        $this->_bend($lc_voice,$lc_new_on);
        $lc_voice->{'on'} = $lc_new_on;
      }
    }
  }

  # Report independently the selected and sounding pitches.
  $lc_result = { 'set' => $lc_voice->{'set'} };

  if ( defined($lc_voice->{'on'}) )
  {
    $lc_result->{'on'} = $lc_voice->{'on'};
  }

  return $lc_result;
}


sub global
{
  # This implementation does not support global bending.
  # Return a fresh empty hashref regardless of arguments.

  my $this;
  $this = shift(@_);

  return {};
}


sub note_on
{
  # Retrigger only this voice, using its selected pitch
  # and establishing a stable MIDI reference note.
  #
  # Notes on other channels remain independent.

  my $this;
  my $lc_number;
  my $lc_options;
  my $lc_voice;
  my $lc_velocity;
  my $lc_pitch;
  my $lc_reference;
  my $lc_status;
  $this = shift(@_);
  $lc_number = shift(@_);
  $lc_options = shift(@_);
  $lc_voice = $this->_voice($lc_number);

  # Validate the voice and options.
  if ( !defined($lc_voice) || ref($lc_options) ne 'HASH' )
  {
    return {};
  }

  $lc_velocity = $lc_options->{'vel'};
  if ( !_number($lc_velocity) ||
       $lc_velocity !~ /\A[0-9]+\z/ ||
       $lc_velocity < 1 || $lc_velocity > 127 )
  {
    return {};
  }

  # Find the MIDI reference note that can reproduce
  # the selected pitch with the configured bend range.
  $lc_pitch = $lc_voice->{'set'};
  $lc_reference = 60 + _round($lc_pitch);

  if ( $this->{'bending'} )
  {
    $lc_reference = $this->_reference($lc_pitch);
  }

  if ( !defined($lc_reference) ) { return {}; }

  # End only the previous note on this voice.
  # This must not affect another channel playing
  # the same MIDI note.
  $this->_stop($lc_voice);

  $lc_voice->{'reference'} = $lc_reference;

  # Establish the initial bend before Note On.
  if ( $this->{'bending'} )
  {
    $this->_bend($lc_voice,$lc_pitch);
  }

  # Start the new note on this voice's dedicated channel.
  $lc_status = 0x90 | $lc_voice->{'channel'};
  $this->_emit(pack('C3',$lc_status,$lc_reference,$lc_velocity));
  $lc_voice->{'on'} = $lc_pitch;

  # Report the new sounding note and its MIDI reference.
  return {
    'on'   => $lc_pitch,
    'ref'  => $lc_reference - 60,
    'bend' => $lc_pitch - ($lc_reference - 60),
  };
}


sub note_off
{
  # End this voice's note alone and report
  # its final sounding pitch.

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
  # Stop any remaining notes and produce the complete
  # MIDI file for this segment.
  #
  # Reset time and event history while preserving
  # every voice's selected pitch.

  my $this;
  my $lc_voice;
  my $lc_event;
  my $lc_delta;
  my $lc_previous;
  my $lc_track;
  my $lc_header;
  my $lc_result;
  $this = shift(@_);

  # End all currently sounding notes.
  foreach $lc_voice (@{$this->{'voices'}})
  {
    $this->_stop($lc_voice);
  }

  # Record MIDI's End of Track meta-event.
  $this->_emit("\xFF\x2F\x00");
  $lc_previous = 0;
  $lc_track = '';

  # Encode the events in their recorded order,
  # using MIDI's variable-length delta times.
  foreach $lc_event (@{$this->{'events'}})
  {
    $lc_delta = $lc_event->[0] - $lc_previous;

    # MIDI delta-time fields cannot exceed 28 bits.
    # Bridge longer silent intervals with inert meta-events.
    while ( $lc_delta > 0x0FFFFFFF )
    {
      $lc_track .= _vlq(0x0FFFFFFF) . "\xFF\x7F\x00";
      $lc_delta -= 0x0FFFFFFF;
    }

    $lc_track .= _vlq($lc_delta) . $lc_event->[1];
    $lc_previous = $lc_event->[0];
  }

  # Assemble the SMF header and its single track.
  $lc_header = 'MThd' . pack(
    'Nnnn',
    6,
    1,
    1,
    $this->{'tpb'}
  );

  $lc_result =
    $lc_header . 'MTrk' . pack('N',length($lc_track)) . $lc_track;

  # Prepare for another output segment.
  $this->{'tick'} = 0;
  $this->{'events'} = [];

  foreach $lc_voice (@{$this->{'voices'}})
  {
    $lc_voice->{'on'} = undef;
    $lc_voice->{'reference'} = undef;
    $lc_voice->{'bend_value'} = 8192;
    $lc_voice->{'bend_sent'} = 0;
    $lc_voice->{'bend_configured'} = 0;
  }

  return $lc_result;
}


1;


