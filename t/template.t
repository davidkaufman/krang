use strict;
use warnings;

use Data::Dumper;
use Krang;
use Test::More qw(no_plan);


BEGIN {use_ok('Krang::Template');}

my $tmpl = Krang::Template->new(category_id => 1,
                                content => '<blink><tmpl_var bob></blink>',
                                element_class => 'Krang::ElementClass::Bob');

isa_ok($tmpl, 'Krang::Template');

# increment version
$tmpl->save();
is($tmpl->version(), 1, 'Version Check');

# write version to version table
$tmpl->prepare_for_edit();

# save description for revert test
my $content = $tmpl->content();

# check Krang::MethodMaker meth...
$tmpl->content('<tmpl_var content>');
my $content2 = $tmpl->content();
is($content2, '<tmpl_var content>', 'Getter/Setter Test');

# increment version
$tmpl->save();
is($tmpl->version(), 2, 'Version Check 2');

# write version 2 to the version table
$tmpl->prepare_for_edit();

# revert check
$tmpl = $tmpl->revert(1);
is($tmpl->content(), $content, 'Revert Test');

# increment version
$tmpl->save();
is($tmpl->version(), 3, 'Version Check 3');

# verify checkin works
$tmpl->checkin();
is($tmpl->checked_out, '', 'Checkin Test');

my $tmpl2 = Krang::Template->new(category_id => 1,
                                 content => '<html></html>',
                                 filename => 't_w_c.tmpl');

$tmpl2->save();
$tmpl2->prepare_for_edit();

# checkout deploy method
my $dir = File::Spec->catdir($ENV{PWD});
my $path = File::Spec->catfile($dir, 't_w_c.tmpl');
$tmpl2->deploy_to($dir);
ok(-e $path, 'Deploy Test');

# find() tests
###############
# make sure find() croaks
eval {Krang::Template->find(count => 1, ids_only => 1)};
is($@ =~ /Only one/, 1, 'Find Failure 1');

eval {Krang::Template->find(XXX => 69)};
is($@ =~ /invalid/, 1, 'Find Failure 2');

my ($tmpl3) = Krang::Template->find(filename_like => '%bob%');
is(ref $tmpl3, 'Krang::Template', "Find - _like 1");

my @ids = ($tmpl->template_id(), $tmpl2->template_id());

my $i = 1;
my @tmpls = Krang::Template->find(template_id => \@ids);
is (ref $_, 'Krang::Template', "Find - template_id " . $i++) for @tmpls;

my $count = Krang::Template->find(count => 1, template_id => \@ids);
is ($count, scalar @ids, "Find - count");

$i = 2;
my @tmpls2 = Krang::Template->find(creation_date_like => '%2003%');
is (ref $_, 'Krang::Template', "Find - _like " . $i++) for @tmpls2;

my ($tmpl4) = Krang::Template->find(limit => 1,
                                    offset => 1,
                                    order_by => 'filename');
is ($tmpl4->filename(), 't_w_c.tmpl', "Find - limit, offset, order_by");

# clean up the mess
unlink 't_w_c.tmpl';
$tmpl->delete();
$tmpl2->delete();

