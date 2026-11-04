use strict;
use warnings;
use ExtUtils::MakeMaker;

package MY;

sub dist_core
{
  # Preserve MakeMaker's distribution machinery, but direct
  # the normal make dist command through our staging utility
  # Inside staging, use MakeMaker's original behavior

  my $this;
  my $lc_rules;
  my $lc_target;

  $this = shift(@_);
  $lc_rules = $this->SUPER::dist_core();

  # Staging uses the ordinary distribution-building process
  if ( $ENV{'PL_MIDI_GEN_RELEASE_STAGE'} )
  {
    return $lc_rules;
  }

  # Replace only the top-level dist target
  $lc_target = <<'MAKE_RULE';
dist : $(FIRST_MAKEFILE)
	$(PERLRUN) tools/release-dist.pl

MAKE_RULE

  $lc_rules =~ s/^dist\s*:.*?(?=^tardist\s*:)/$lc_target/ms
    or die "Cannot customize MakeMaker dist target\n";

  return $lc_rules;
}

package main;

WriteMakefile(
  'NAME' => 'Pl_MIDI_Gen',
  'VERSION_FROM' => 'lib/Pl_MIDI_Gen.pm',
  'LICENSE' => 'lgpl_2_1',
);


