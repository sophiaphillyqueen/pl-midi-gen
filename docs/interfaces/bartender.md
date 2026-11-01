# Pl_MIDI_Gen — Bartender Interface

## Purpose

The `Pl_MIDI_Gen` package serves as the bartender for the
`Pl_MIDI_Gen` library, facilitating the loading and construction
of implementation engines, musical instrument controllers,
and library utilities.

It supports three loading mechanisms:

| Method | Loading mechanism |
|---|---|
| `fromus` | Modules within the `Pl_MIDI_Gen` namespace |
| `from_pl_all` | Installed Perl modules available through `@INC` |
| `fsplug` | External Perl source files, or additional instances of existing plug-in objects |

The bartender is specifically intended for the needs of
`Pl_MIDI_Gen`, not as a general-purpose Perl plug-in framework.

## Constructor

### `Pl_MIDI_Gen->new($external_namespace)`

Creates a bartender object and initializes the class-wide
external plug-in namespace on the first successful invocation.

**First successful construction:**

- Exactly one argument required
- Argument must be a non-reference scalar
- Namespace must match:

```perl
/\A[A-Z][A-Za-z0-9_]*_[A-Za-z0-9]+\z/
```

Example:

```perl
my $bartender = Pl_MIDI_Gen->new('MyPlugin_App');
```

**Subsequent construction:**

- No argument requirements
- All supplied arguments ignored
- Fresh, empty bartender object returned
- Previously established external namespace preserved

**Return value:**

| Condition | Return |
|---|---|
| Successful construction | Blessed bartender object |
| Invalid initial namespace or argument count | `undef` |

Failed initialization does not prevent a later successful
initialization attempt.

### Shared state

The following state belongs to the class rather than to
individual bartender objects:

- Initialization status
- External plug-in namespace
- Next external package number
- Registry of loaded external plug-in files

## Loading methods

### `fromus($short_package_name, @constructor_args)`

Loads a module from the library's own `Pl_MIDI_Gen` namespace.

The supplied package name is prefixed with `Pl_MIDI_Gen::`
and passed to `from_pl_all()`.

Examples:

```perl
my $engine = $bartender->fromus(
  'Impl::MIDI1_SingleChan',
  \@open_pitches,
  \%options
);

my $pitch_utility = $bartender->fromus('Util::Pitch');
```

**Arguments:**

| Argument | Meaning |
|---|---|
| `$short_package_name` | Package name relative to `Pl_MIDI_Gen::` |
| `@constructor_args` | Arguments forwarded to the loaded module's constructor |

**Return:** Result of `from_pl_all()`, including `undef` on loading failure

---

### `from_pl_all($package_name, @constructor_args)`

Loads an ordinary Perl module by its fully qualified package
name using Perl's standard `require` mechanism and `@INC`.

Example:

```perl
my $object = $bartender->from_pl_all(
  'Some::Installed::Module',
  @arguments
);
```

**Arguments:**

| Argument | Meaning |
|---|---|
| `$package_name` | Fully qualified Perl package name |
| `@constructor_args` | Arguments forwarded to the module's constructor |

**Package-name validation:**

```perl
/\A[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*\z/
```

**Behavior:**

- Requires successful bartender initialization
- Validates the package name
- Loads through Perl's `require`
- Relies on `%INC` to avoid reloading an existing module
- Invokes the module's `new()` constructor

**Constructor invocation:**

```perl
$package_name->new($bartender, @constructor_args)
```

**Return:** Constructor result, or `undef` for validation or loading failure

---

### `fsplug($plugin, @constructor_args)`

Loads an external plug-in source file, or constructs another
instance of the class of an existing plug-in object.

The first argument determines which operation is performed.

#### File-based loading

Example:

```perl
my $plugin = $bartender->fsplug(
  '/path/to/custom-plugin.mdgn',
  @arguments
);
```

**Behavior:**

1. Resolve the filename using `abs_path()`
2. Require an existing regular file
3. Check the class-wide registry for an existing loaded copy
4. Read the complete source file if not already loaded
5. Assign an automatically generated package name
6. Prepend the package declaration to the source
7. Evaluate the source as Perl
8. Register successfully loaded source by canonical filename
9. Invoke the resulting package's `new()` constructor

**Generated package names:**

```text
<external_namespace>::a_<number>_z
```

For example:

```text
MyPlugin_App::a_1_z
MyPlugin_App::a_2_z
```

**External source requirements:**

- Perl source code
- No explicit `package` declaration
- A `new()` constructor for object creation
- No specific filename extension required
- Optional source-level `strict` and `warnings` declarations

Source compilation failures consume an assigned package
number but do not register the failed file.

#### Existing-object construction

Example:

```perl
my $another = $bartender->fsplug(
  $existing_plugin,
  @arguments
);
```

When `$plugin` is a blessed object, the bartender obtains
its class and invokes that class's constructor again.

**Constructor invocation:**

```perl
ref($existing_plugin)->new($bartender, @arguments)
```

No filename resolution or source evaluation is needed.

#### File identity and caching

- Cache key: canonical absolute filename
- Relative paths supported
- Symbolic links resolved through `abs_path()`
- Repeated loading of the same canonical file reuses its package
- A new object constructed on every successful invocation

## Common constructor contract

Modules and external plug-ins loaded by the bartender receive
the bartender object as their first constructor argument,
followed by the arguments originally supplied by the caller.

Conceptual constructor:

```perl
sub new
{
  my $this;
  my $lc_bartender;

  $this = shift(@_);
  $lc_bartender = shift(@_);

  # Remaining arguments are specific to this component.
}
```

## Failure behavior

| Condition | Behavior |
|---|---|
| Invalid initial namespace | `undef` |
| Invalid module package name | `undef` |
| Module loading failure | `undef` |
| External source file missing | `undef` |
| External source unreadable | `undef` |
| External source evaluation failure | `undef` |
| Constructor returns `undef` | `undef` passed through |
| Constructor throws an exception | Exception propagated |

Constructor exceptions are not intercepted by the bartender,
regardless of the loading method.

## Scope and lifecycle

- One initialization namespace per Perl process
- Multiple bartender objects permitted
- Shared external-file registry across bartender objects
- No public reset or reinitialization method
- No automatic unloading of loaded modules
- No modification of Perl's ordinary `@INC` search rules
- No requirement to use the bartender for ordinary Perl modules
  that do not participate in this library's loading mechanisms


