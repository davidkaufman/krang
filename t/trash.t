use Krang::ClassFactory qw(pkg);
use Test::More qw(no_plan);
use strict;
use warnings;
use Krang::ClassLoader 'Script';
use Krang::ClassLoader 'Site';
use Krang::ClassLoader 'Category';
use Krang::ClassLoader Conf => qw(InstanceElementSet);

# use the TestSet1 instance, if there is one
foreach my $instance (pkg('Conf')->instances) {
    pkg('Conf')->instance($instance);
    if (InstanceElementSet eq 'TestSet1') {
        last;
    }
}

BEGIN { use_ok(pkg('Trash')) }

# create a site and some categories to put stories in
my $site = pkg('Site')->new(preview_url  => 'storytest.preview.com',
                            url          => 'storytest.com',
                            publish_path => '/tmp/storytest_publish',
                            preview_path => '/tmp/storytest_preview');
isa_ok($site, 'Krang::Site');
$site->save();
END { $site->delete() }
my ($root_cat) = pkg('Category')->find(site_id => $site->site_id, dir => "/");
isa_ok($root_cat, 'Krang::Category');
$root_cat->save();

my @cat;
for (0 .. 10) {
    push @cat, pkg('Category')->new(site_id   => $site->site_id,
                                    parent_id => $root_cat->category_id,
                                    dir       => 'test_' . $_);
    $cat[-1]->save();
}

# cleanup the mess
END {
    $_->delete for @cat;
}

SKIP: {
    skip('Story tests only work for TestSet1', 1)
      unless (InstanceElementSet eq 'TestSet1');

    # create 10 stories
    my @stories;
    for my $n (0 .. 9) {
        my $story = pkg('Story')->new(categories => [$cat[$n]],
                                      title      => "Test$n",
                                      slug       => "test$n",
                                      class      => "article");
        $story->save();
        push(@stories, $story);
    }
    END { $_->delete for @stories }

    # move them to the trashbin
    $_->trash for @stories;

    # test trash find with just stories
    my @trash = pkg('Trash')->find();
    ok(not grep { not defined $_ } @trash);
    foreach my $story (@stories) {
        ok(grep{ $story->story_id == $_->{id} } @trash);
    }

    # restore a story and make sure it's gone from the trashbin
    $stories[0]->untrash;
    @trash = pkg('Trash')->find();
    ok(not grep { $_->{id} == $stories[0]->story_id } @trash);
};

