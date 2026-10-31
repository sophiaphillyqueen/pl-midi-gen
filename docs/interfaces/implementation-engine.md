# Pl_MIDI_Gen — Implementation Engine Interface Specification

## 1. Purpose

An implementation engine provides the low-level functionality required
to generate musical output.

The high-level instrument implementations delegate their output
generation to these engines.

An implementation engine need not represent a particular musical
instrument.

## 2. Construction

### Constructor

    new($bartender, \@starting_pitches, \%options)

The bartender supplies its own object as the first constructor
argument, followed by the arguments supplied by its caller.

Parameters:

- `$bartender` — The bartender object.
- `\@starting_pitches` — Initial pitches for the available voices.
- `\%options` — Constructor options.

The number of elements in `@starting_pitches` determines the number
of voices requested.

Voices are numbered from 1, corresponding to the array's element
order.

The starting pitches establish each voice's initial selected pitch,
which is used if `note_on()` precedes its first `set_pitch()` call.

### Constructor options

General options established so far:

| Key | Meaning |
|---|---|
| `bend_up` | Upward pitch-bend range in semitones |
| `bend_down` | Downward pitch-bend range in semitones |
| `bend_prt` | Whether out-of-range bends proceed partway |
| `engopt` | Optional hashref of engine-specific options |

Both `bend_up` and `bend_down` must be supplied to enable
fractional-pitch functionality.

If an implementation does not support the relevant bending
functionality, the associated options have no effect.

`bend_prt`:

- `1` (default): Bend as far as the permitted range allows.
- `0`: Do not bend unless the requested pitch is reachable.

Engine-specific options belong inside `engopt`, rather than in
the main options namespace.

A constructor may return `undef` on failure.

Constructor exceptions are not trapped by the bartender.


## 3. Pitch Representation

Pitch values are real numbers representing semitone offsets from C4.

Examples:

| Pitch | Value |
|---|---:|
| C3 | -12 |
| C4 | 0 |
| C#4 / Db4 | 1 |
| D4 | 2 |
| A4 | 9 |
| C5 | 12 |

Fractional values represent pitches between semitones.

Examples:

- `0.5`: Halfway between C4 and C#4
- `-0.5`: Halfway between B3 and C4

Enharmonic spellings are immaterial to the engine.


## 4. Required Methods

### capabilities()

Class method; no constructed engine object required.

Returns a fresh hashref containing:

| Key | Meaning |
|---|---|
| `max_voices` | Maximum supported independent voices |
| `fractional_pitch` | Supports noninteger pitches |
| `continuous_pitch` | Supports changing a sounding note's pitch |
| `ind_same_pitch` | Supports independently controlled voices sounding the same pitch |
| `extension` | Recommended output filename extension, without a leading period |

The returned structure must be independent of internal storage,
including any nested mutable structures.

Capabilities describe implementation support, not necessarily
features enabled by the constructor options.


### ticks_forward($ticks)

Argument:

- `$ticks` — Optional nonnegative integer number of ticks.

Behavior:

- Advance the musical clock by the specified amount.
- No argument: advance by zero ticks.
- Explicit zero: advance by zero ticks.
- Backward time movement is not supported.

Return:

- The current absolute tick position after the operation.

Examples:

    $engine->ticks_forward(30);
    $position = $engine->ticks_forward(0);
    $position = $engine->ticks_forward();


### set_pitch($voice, $pitch)

Arguments:

- `$voice` — One-based voice number.
- `$pitch` — Requested pitch in semitones relative to C4.

Behavior:

- Establish the selected pitch for the specified voice.
- Do not terminate an already sounding note.
- If continuous pitch changes are unavailable, leave the
  sounding note unchanged.
- If continuous pitch changes are enabled, attempt to bend
  the sounding note toward the selected pitch.
- Apply `bend_prt` if the requested pitch cannot be reached.
- If fractional pitches are unavailable, use an integer
  pitch supported by the implementation.

Return:

A newly allocated hashref containing:

| Key | Meaning |
|---|---|
| `set` | Pitch actually selected for the voice |
| `on` | Actual pitch currently sounding, if any |

The `set` key is always present after a successful operation.

The `on` key is present only when the voice is sounding.

The values may differ.

The returned hashref is disposable and must not expose mutable
internal engine state.


### note_on($voice, \%options)

Arguments:

- `$voice` — One-based voice number.
- `\%options` — Note-start options hashref.

Required option:

- `vel` — Note velocity.

Behavior:

- Terminate any note already sounding on this voice.
- Begin a new note using the voice's selected pitch.
- Establish the appropriate starting reference pitch when
  the implementation supports pitch bending.

Return:

- On failure, return a fresh, empty hashref (`{}`).

- On success, a fresh hashref containing:
  - `on` — The actual pitch of the newly sounding note, expressed
    in semitones relative to C4.
  - `ref` — The MIDI reference pitch (home note) selected for the
    newly sounding note, expressed in semitones relative to C4.
  - `bend` — The initial pitch-bend offset, expressed in semitones
    relative to the MIDI reference pitch (`on` minus `ref`).


### note_off($voice)

Argument:

- `$voice` — One-based voice number.

Behavior:

- Terminate the note currently sounding on that voice.
- If already silent, do nothing.

Return:

- Pitch of the note just terminated.
- `undef` if the voice was already silent.

Pitch zero is valid and must not be confused with `undef`.


### end()

Arguments:

- None.

Behavior:

- Terminate every currently sounding note.
- Finalize the current output segment.
- Prepare the engine for another segment.
- Reset the musical clock to zero.

Return:

- Complete raw binary output for the finalized segment.


## 5. Voice State

Each voice maintains, at minimum:

- Its selected pitch.
- Whether a note is currently sounding.
- The actual sounding pitch, when applicable.

An implementation supporting continuous pitch changes must also
maintain whatever reference-pitch and bend information is necessary.

Voices are independently addressable.

Their maximum number and ability to coexist at identical pitches
are reported through `capabilities()`.


## 6. Pitch-Bending Rules

When pitch bending is unavailable:

- `set_pitch()` changes the selected pitch.
- A sounding note remains at its existing pitch.
- The next `note_on()` uses the newly selected pitch.

When pitch bending is enabled:

- `set_pitch()` attempts to change the sounding pitch.
- The current note's starting reference determines its bend limits.
- A requested pitch outside those limits cannot be reached
  through bending alone.

With `bend_prt = 1`:

- The sounding pitch moves to the nearest reachable limit.

With `bend_prt = 0`:

- An unreachable request leaves the sounding pitch unchanged.

In either case:

- The selected pitch is updated.
- `set_pitch()` reports both selected and sounding pitches
  when a note is active.
- The next `note_on()` may establish a new reference pitch.

### Anchor stability of a sounding note

When `note_on()` starts a note on a voice, the implementation must select
the MIDI reference note whose pitch is closest to the voice's selected
pitch at the moment `note_on()` is called, among those MIDI notes
from which the selected pitch can be reached using the configured
pitch-bend limits.

Once established, the reference pitch must remain unchanged for the
entire duration of that sounding note, regardless of subsequent calls
to `set_pitch()`.

This requirement applies even when `set_pitch()` is called immediately
after `note_on()`, without any intervening call to `ticks_forward()`.

Subsequent pitch changes must be accomplished through pitch-bending
relative to the established reference pitch, subject to the configured
bending limits, rather than by selecting a new reference pitch.

A new reference pitch may be established only when a subsequent
`note_on()` starts a new note on that voice.


## 7. Implementation Independence

The generic interface does not prescribe:

- MIDI file format or version.
- MIDI channel allocation.
- MIDI track organization.
- A particular pitch-bend encoding.
- A particular output filename extension.
- A particular internal representation of voices.

Those are responsibilities of individual implementation engines.

The first approved engine is:

    Pl_MIDI_Gen::Impl::MIDI1

Its MIDI1-specific choices belong in its implementation
documentation, not in this generic interface.


