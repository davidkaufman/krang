package Krang::CGI::Publisher;
use strict;
use warnings;

=head1 NAME

Krang::CGI::Publisher - the publisher frontend

=head1 SYNOPSIS

None.

=head1 DESCRIPTION

This application provides a frontend to Krang::Publisher 

=head1 INTERFACE

=head2 Run-Modes

=over 4

=cut

use Krang::Session qw(%session);
use Krang::Publisher;
use Krang::Story;
use Krang::User;
use Krang::Log qw(debug critical assert ASSERT);
use Krang::Widget qw(format_url datetime_chooser decode_datetime);
use Krang::Message qw(add_message get_messages clear_messages);
use Time::Piece;

use Carp qw(croak);

use base 'Krang::CGI';

sub setup {
    my $self = shift;
    $self->start_mode('preview_story');
    $self->mode_param('rm');
    $self->tmpl_path('Publisher/');
    $self->run_modes([qw(
                         preview_story
                         preview_media
                         publish_story
                         publish_story_list
                         publish_assets
                         publish_media
    )]);

}


=item publish_story

Presents a list of story and media objects to be published.  Allows
the user to schedule a publish date.

Requires story_id parameter with the ID of the story to be published.

=cut

sub publish_story {
    my $self = shift;
    my $query = $self->query;

    my $story_id = $query->param('story_id');
    croak("Missing required story_id parameter") unless $story_id;

    $query->delete('story_id');

    $story_id =~ s/^story_(\d+)$/$1/go;

    my ($story) = Krang::Story->find(story_id => $story_id);

    croak("Unable to load story for story_id '$story_id'")
      unless $story;

    my $t = $self->load_tmpl('publish_list.tmpl',
                             associate => $query,
                             loop_context_vars => 1,
                             die_on_bad_params => 0
                            );

    my ($stories, $media, $checked_out) = $self->_build_asset_list([$story]);

    add_message('checked_out_assets') if ($checked_out);

    $t->param(stories => $stories, media => $media);
    $t->param(asset_id_list => [{id => "story_$story_id"}]);

    # add date chooser
    $t->param(publish_date_chooser => datetime_chooser(name => 'publish_date',
                                                       query => $query,
                                                       onchange => 'document.forms[0].publish_now[1].checked = true;',
                                                      ));

    return $t->output();

}


=item publish_story_list

Presents a list of story and media objects to be published.  Allows
the user to schedule a publish date.

Requires story_id_list parameter with the IDs of the story to be published.

=cut

sub publish_story_list {
    my $self = shift;
    my $query = $self->query;

    my (@story_list,@media_list,@story_id_list,@media_id_list,
        @template_id_list);

    my @asset_id_list = $query->param('krang_pager_rows_checked');

    my $t = $self->load_tmpl('publish_list.tmpl',
                             associate => $query,
                             loop_context_vars => 1,
                             die_on_bad_params => 0
                            );
    my @id_list;

    foreach (@asset_id_list) {
        push @id_list, { id => $_ };
        push(@story_id_list, $1), next if /^(\d+)$/;

        if (/^(\w+)_(\d+)$/) {
            push(@story_id_list, $2), next if $1 eq 'story';
            push(@media_id_list, $2), next if $1 eq 'media';
            push(@template_id_list, $2), next if $1 eq 'template';
        }
        croak __PACKAGE__ . ": what to do with asset = '$1'??";
    }


    $t->param(asset_id_list => \@id_list);

    # take care of templates first, they don't go to the next screen
    if (@template_id_list) {
        my $publisher = Krang::Publisher->new();
        foreach my $template_id (@template_id_list) {
            my ($template) = Krang::Template->find(template_id =>$template_id);
            add_message('deployed', id => $template_id);
            $publisher->deploy_template(template => $template);
            $template->checkin;
        }
    }

    # if there are no stories and media, return to workspace directly
    unless (@story_id_list or @media_id_list) {
        $self->header_props(-uri => 'workspace.pl');
        $self->header_type('redirect');
        return "";
    }

    @story_list = Krang::Story->find(story_id => \@story_id_list) if @story_id_list;
    @media_list = Krang::Media->find(media_id => \@media_id_list) if @media_id_list;

    my ($stories, $media, $checked_out) = $self->_build_asset_list(\@story_list, \@media_list);

    add_message('checked_out_assets') if ($checked_out);

    $t->param(stories => $stories, media => $media);

    # add date chooser
    $t->param(publish_date_chooser => 
              datetime_chooser(name => 'publish_date',
                               query => $query,
                               onchange => 'document.forms[0].publish_now[1].checked = true;')
             );
    return $t->output();

}


=item publish_assets

Starts the publish process for a given set of stories stories specified by the CGI parameter 'asset_publish_list'.

B<NOTE>: 'asset_publish_list' does not necessarily contain all items listed when the publish process is initiated - it only lists 

Requires the following parameters: story_ids, publish_now, publish_date_xxx (if publish_now == 0)

If publish_now == 1, start publish, show a status bar then redirect to workspace.

If putlist_now == 0, schedule publish & redirect to workspace.

=cut

sub publish_assets {
    my $self = shift;
    my $query = $self->query;

    my @asset_id_list = ( $query->param('asset_id_list') );
    croak("Missing required asset_id_list parameter") unless @asset_id_list;
    my $publish_now = $query->param('publish_now');

    my @story_id_list;
    my @media_id_list;

    my @story_list;
    my @media_list;

    foreach (@asset_id_list) {
        push(@story_id_list, $1), next if /^(\d+)$/;

        if (/^(\w+)_(\d+)$/) {
            push(@story_id_list, $2), next if $1 eq 'story';
            push(@media_id_list, $2), next if $1 eq 'media';            
        }
        croak __PACKAGE__ . ": what to do with asset = '$1'??";
    }

    @story_list = Krang::Story->find(story_id => \@story_id_list) if @story_id_list;
    @media_list = Krang::Media->find(media_id => \@media_id_list) if @media_id_list;

    if ($publish_now) {
        $self->_publish_assets_now(\@story_list, \@media_list);
    } else {
        # pass things to the scheduler
        my $date = decode_datetime(name => 'publish_date', query => $query);
        $self->_schedule_assets(\@story_list, \@media_list, $date);

        # return to my workspace
        $self->header_props(-uri => 'workspace.pl');
        $self->header_type('redirect');
        return "";
    }

}


=item publish_media

Publishes a media object immediately.  No scheduling done here.

requires media_id

returns the user to 'My Workspace' when done.

=cut

sub publish_media {
    my $self = shift;
    my $query = $self->query;

    my $media_id = $query->param('media_id');
    croak("Missing required media_id parameter") unless $media_id;

    $media_id =~ s/^media_(\d+)$/$1/go;
    my ($media) = Krang::Media->find(media_id => $media_id);

    # run things to the publisher
    my $publisher = Krang::Publisher->new();
    $publisher->publish_media(media => $media);
    # add a message
    add_message('media_publish', media_id => $media_id,
                url => $media->url,
                version => $media->version);

    # return to my workspace
    $self->header_props(-uri => 'workspace.pl');
    $self->header_type('redirect');
    return "";

}



=item preview_story

Publishes a story to preview and returns a redirect to the resulting
page on the preview story.  Requires a story_id parameter with the ID
for the story to be previewed or a session parameter set to the
session key containing the story to preview.

=cut

sub preview_story {
    my $self = shift;
    my $query = $self->query;

    # this is a no-parse header script
    $self->header_type('none');
    print $query->header(-expires => '-1d');

    my $session_key = $query->param('session');
    my $story_id    = $query->param('story_id');
    croak("Missing required story_id or session parameter.")
      unless $story_id or $session_key;

    my $story;

    my $unsaved = 0;

    unless ($session_key) {
        ($story) = Krang::Story->find(story_id => $story_id);
        croak("Unable to find story '$story_id'")
          unless $story;
    } else {
        $story = $session{$session_key};
        croak("Unable to load story from sesssion '$session_key'")
          unless $story;
        $unsaved = 1 if ($session_key eq 'story');
    }

    # output the progress header
    my $template = $self->load_tmpl('progress.tmpl');
    $template->param(preview => 1);
    $|++;
    print $template->output;

    # start up the cache and setup an eval{} to catch any death
    Krang::Cache::start();
    my $url;
    eval {

        my $publisher = Krang::Publisher->new();
        eval {
            $url = $publisher->preview_story(story    => $story, 
                                             callback =>\&_progress_callback,
                                             unsaved  => $unsaved
                                            );
        };
        if (my $err = $@) {
            # if there is an error, figure out what it is, create the
            # appropriate message and return an error page.
            if (ref $@ && $@->isa('Krang::ElementClass::TemplateNotFound')) {
                add_message('missing_template',
                            filename       => $@->template_name,
                            category_url   => $@->category_url
                       );
            } elsif (ref $@ && $@->isa('Krang::ElementClass::TemplateParseError')) {
                add_message('template_parse_error',
                            element_name  => $@->element_name,
                            template_name => $@->template_name,
                            category_url  => $@->category_url,
                            error_msg     => $@->message
                           );
            } elsif (ref $@ and $@->isa('Krang::Publisher::FileWriteError')) {
                add_message('file_write_error',
                            path          => $@->destination);
            } else {
                # something not expected so log the error.  Can't croak()
                # here because that will trigger bug.pl.
                print "<div class='alertp'>An internal server error occurred.  Please check the error logs for details.</div>\n";
                critical($@);
            }

            # put the messages on the screen
            foreach my $error (get_messages()) {
                print "<div class='alertp'>" . $query->escapeHTML($error) . 
                  "</div>\n";
            }
            clear_messages();

            # make sure to turn off caching
            Krang::Cache::stop();
            debug("Krang::Cache Stats " . join(' : ', Krang::Cache::stats()));

            die $err;
        }
    };
    my $err = $@;

    # cache off, regardless of $err
    Krang::Cache::stop();
    debug("Krang::Cache Stats " . join(' : ', Krang::Cache::stats()));

    # die a rightful death
    die $err if $err;

    # this should always be true
    assert($url eq $story->preview_url) if ASSERT;

    # dynamic redirect to preview
    print "<script language='javascript'>window.location = 'http://$url'</script>\n";
}

# update the progress bar during preview or publish
sub _progress_callback {
    my %arg = @_;
    my ($object, $counter, $total) = @arg{qw(object counter total)};
    my $string;
    if ($object->isa('Krang::Story')) {
        $string = "Story " . $object->story_id . ": " . $object->url;
    } else {
        $string = "Media " . $object->media_id . ": " . $object->url;
    }
    print "<script language='javascript'>update_progress_bar($counter, $total, '$string');</script>\n";
}

=item preview_media

Publishes a media object to preview and returns a redirect to the
resulting URL.  Requires a media_id parameter with the ID for the
media to be previewed, or a parameter called session set to the
session key containing the media object.

=cut

sub preview_media {
    my $self = shift;
    my $query = $self->query;

    my $session_key = $query->param('session');
    my $media_id    = $query->param('media_id');
    croak("Missing required media_id or session parameter.")
      unless $media_id or $session_key;

    my $media;
    unless ($session_key) {
        ($media) = Krang::Media->find(media_id => $media_id);
        croak("Unable to find media '$media_id'")
          unless $media;
    } else {
        $media = $session{$session_key};
        croak("Unable to load media from sesssion '$session_key'")
          unless $media;
    }

    my $publisher = Krang::Publisher->new();
    my $url;
    eval { $url = $publisher->preview_media(media => $media); };
    if (my $e = $@) {
        # load the error screen template, one way or another we'll
        # need it.
        my $template = $self->load_tmpl('media_error.tmpl');
        my @error_loop;

        if (ref $e and $e->isa('Krang::Publisher::FileWriteError')) {
            add_message('file_write_error',
                        path          => $e->destination);
            # put the messages on the screen
            foreach my $err (get_messages()) {
                push(@error_loop, { err => $err });
            }
            clear_messages();
        } else {
            # something not expected so log the error.  Can't croak()
            # here because that will trigger bug.pl.
            push(@error_loop, 'An internal server error occurred.  Please check the error logs for details.');
            critical($e);
        }

        # finish the error screen
        $template->param(error_loop => \@error_loop);
        return $template->output;
    }

    # redirect to preview
    $self->header_type('redirect');
    $self->header_props(-url=>"http://$url");
    return "Redirecting to <a href='http://$url'>http://$url</a>.";
}



#
# given a list of stories, build the @stories and @media lists
# for assets linked to by these stories.
#
sub _build_asset_list {
    my $self = shift;
    my ($story_list, $media_list) = @_;

    my $user_id = $ENV{REMOTE_USER};

    my $publish_list = [];
    my @stories = ();
    my @media = ();

    my $publisher = Krang::Publisher->new();

    # retrieve all stories linked to the submitted list.
    push(@{$publish_list}, 
         @{$publisher->asset_list(story => $story_list, mode => 'publish')})
      if $story_list and @$story_list;

    # add previously submitted media objects to the list.
    push(@{$publish_list}, @$media_list)
      if $media_list and @$media_list;

    my $checked_out_assets = 0;
    # iterate over asset list to create display list.
    foreach my $asset (@$publish_list) {
        my $checked_out = 0;
        my $status      = '';
        # deal w/ checked out assets - a problem if assets are checked
        # out by a user other than the current user.
        if ($asset->checked_out) {
            my $checked_out_by = $asset->checked_out_by();
            if ($user_id != $checked_out_by) {
                $checked_out = 1;
                $status = 'Checked out by <b>' .
                  (Krang::User->find(user_id => $asset->checked_out_by))[0]->login .
                    '</b>';
            }
        }
        $checked_out_assets = $checked_out if $checked_out;

        if ($asset->isa('Krang::Story')) {
            push @stories, {id          => $asset->story_id,
                            url         => format_url(url    => $asset->url,
                                                      linkto => "javascript:preview_story('" . $asset->story_id . "')",
                                                      length => 20
                                                     ),
                            title       => $asset->title,
                            checked_out => $checked_out,
                            status      => $status
                           };
        } elsif ($asset->isa('Krang::Media')) {
            push @media, {id          => $asset->media_id,
                          url         => format_url(url    => $asset->url,
                                                    linkto => "javascript:preview_media('".$asset->media_id."')",
                                                    length => 20
                                                 ),
                          title       => $asset->title,
                          thumbnail   => $asset->thumbnail_path(relative => 1) || '',
                          checked_out => $checked_out,
                          status      => $status
                         };

        } else {
            # Nothing else should make it this far.
            croak sprintf("%s: I have no idea what to do with this: ISA='%s'", __PACKAGE__, $_->isa());
        }
    }

    return (\@stories, \@media, $checked_out_assets);

}


#
# _publish_assets_now($story_list_ref, $media_list_ref);
#
# Given lists of story & media objects, start the publish process on both.
# If errors occur, make entires in the message system & return.
#
sub _publish_assets_now {
    my $self = shift;
    my ($story_list, $media_list) = @_;
    my $query = $self->query;

    # this is a no-parse header script
    $self->header_type('none');
    print $query->header;

    # output the progress header
    my $template = $self->load_tmpl('progress.tmpl');
    $|++;
    print $template->output;

    # start caching and setup an eval{} to catch death
    Krang::Cache::start();
    eval {

        # run things to the publisher
        my $publisher = Krang::Publisher->new();
        if (@$story_list) {
            # publish!
            eval {
                $publisher->publish_story(story    => $story_list,
                                          callback =>\&_progress_callback);
            };

            if (my $err = $@) {
                # if there is an error, figure out what it is, create the
                # appropriate message and return.
                if (ref $err &&
                    $err->isa('Krang::ElementClass::TemplateNotFound')) {
                    add_message('missing_template',
                                filename     => $err->template_name,
                                category_url => $err->category_url
                               );
                    critical(sprintf("Unable to find template '%s' for Category '%s'",
                                     $err->template_name, $err->category_url));

                } elsif (ref $err &&
                         $err->isa('Krang::ElementClass::TemplateParseError')) {
                    add_message('template_parse_error',
                                element_name  => $err->element_name,
                                template_name => $err->template_name,
                                category_url  => $err->category_url,
                                error_msg     => $err->message
                               );
                    critical($err->error_msg)
                } elsif (ref $err &&
                         $err->isa('Krang::Publisher::FileWriteError')) {
                    add_message('file_write_error',
                                path => $err->destination);
                    critical(sprintf("Unable to write file to '%s'", $err->destination));
                } else {
                    # something not expected so log the error.  Can't croak()
                    # here because that will trigger bug.pl.
                    die $err;
                }

                # make sure to turn off caching
                Krang::Cache::stop();
                debug("Krang::Cache Stats " . join(' : ', Krang::Cache::stats()));

                return;

            } else {

                # otherwise, we're good.
                foreach my $story (@$story_list) {
                    # add a publish message for the UI
                    add_message('story_publish', story_id => $story->story_id,
                                url => $story->url,
                                version => $story->version);
                }
            }
        }

        if (@$media_list) {
            # publish!
            $publisher->publish_media(media => $media_list);
            foreach my $media (@$media_list) {
                # add a publish message for the UI
                add_message('media_publish', media_id => $media->media_id,
                            url => $media->url,
                            version => $media->version);
            }
        }
    };
    my $err = $@;

    # done caching
    Krang::Cache::stop();
    debug("Krang::Cache stats " . join(' : ', Krang::Cache::stats()));

    # die if you want to
    die $err if $err;

    # dynamic redirect to workspace
    print "<form action=workspace.pl></form><script language='javascript'>document.forms[0].submit();</script>\n";

    return;
}


#
# _schedule_assets($story_listref, $media_listref, $date);
#
# Takes lists of story & media objects and makes entries for them in the scheduler.
#

sub _schedule_assets {

    my $self = shift;
    my ($story_list, $media_list, $date) = @_;

    foreach my $story (@$story_list) {
        my $sched = Krang::Schedule->new(object_type => 'story',
                                         object_id   => $story->story_id,
                                         action      => 'publish',
                                         repeat      => 'never',
                                         date        => $date);
        $sched->save();
        add_message('story_schedule',
                    story_id => $story->story_id,
                    version => $story->version,
                    publish_datetime => $date->cdate()
                   );
        # check scheduled story back in.
        $story->checkin();

    }
    foreach my $media (@$media_list) {
        my $sched = Krang::Schedule->new(object_type => 'media',
                                         object_id   => $media->media_id,
                                         action      => 'publish',
                                         repeat      => 'never',
                                         date        => $date);
        $sched->save();
        add_message('media_schedule',
                    media_id => $media->media_id,
                    version => $media->version,
                    publish_datetime => $date->cdate()
                   );
        $media->checkin();
    }

    return;

}


1;

=back

=cut

