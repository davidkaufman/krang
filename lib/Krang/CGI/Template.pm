package Krang::CGI::Template;

=head1 NAME

Krang::CGI::Template - Module what manages templates

=head1 SYNOPSIS

  use Krang::ClassLoader 'CGI::Template';
  my $app = pkg('CGI::Template')->new();
  $app->run();


=head1 DESCRIPTION

This module provide the end-user interface to template objects.  Here, users
may search for, view, edit, and create templates.

=cut

use Krang::ClassFactory qw(pkg);
use strict;
use warnings;
use Krang::ClassLoader base => qw/CGI/;

use Carp qw(verbose croak);

use Krang::ClassLoader 'History';
use Krang::ClassLoader 'HTMLPager';
use Krang::ClassLoader Log     => qw/critical debug info/;
use Krang::ClassLoader Message => qw/add_message add_alert/;
use Krang::ClassLoader 'Pref';
use Krang::ClassLoader Session => qw/%session/;
use Krang::ClassLoader 'Template';
use Krang::ClassLoader Widget => qw/
  format_url
  category_chooser
  template_chooser
  template_chooser_object
  autocomplete_values
  /;
use Krang::ClassLoader 'Publisher';

# Persist data for return from view in "history_return_params"
our @history_param_list = (
    'rm',                          'krang_pager_curr_page_num',
    'krang_pager_show_big_view',   'krang_pager_sort_field',
    'krang_pager_sort_order_desc', 'search_below_category_id',
    'search_element',              'search_filename',
    'search_filter',               'search_template_id',
    'search_url',
);

##############################
#####  OVERRIDE METHODS  #####
##############################

sub setup {
    my $self = shift;

    $self->start_mode('search');

    $self->run_modes(
        [
            qw/
              add
              add_cancel
              add_save
              add_checkin
              add_save_stay
              advanced_search
              cancel_add
              cancel_edit
              checkin_selected
              delete
              delete_selected
              deploy
              deploy_selected
              checkout_and_edit
              edit
              edit_cancel
              edit_save
              edit_checkin
              edit_save_stay
              list_active
              list_retired
              revert_version
              save_and_view_log
              view_log
              search
              view
              view_edit
              view_version
              autocomplete
              template_chooser_node
              retire
              unretire
              /
        ]
    );

    $self->tmpl_path('Template/');

}

=head1 INTERFACE

=head2 RUN MODES

=cut

##############################
#####  RUN-MODE METHODS  #####
##############################

=over 4

=item add

This screen allows the end-user to add a new Template object.

=cut

sub add {
    my $self = shift;
    my %args = @_;
    my $q    = $self->query();
    my $template;

    $q->param('add_mode', 1);

    if ($q->param('errors')) {
        $template = $session{template};
    } else {
        $template = pkg('Template')->new();
    }

    # add template to session
    $session{template} = $template;

    my $t = $self->load_tmpl(
        'edit.tmpl',
        associate         => $q,
        loop_context_vars => 1
    );

    $t->param($self->get_tmpl_params($template));

    $t->param(%args) if %args;

    return $t->output();
}

=item add_cancel

Cancels edit of template object on "Add" screen and returns to 'search' run
mode.

=cut

sub add_cancel {
    my $self = shift;

    my $q = $self->query();

    add_message('message_add_cancelled');

    return $self->search();
}

=item add_checkin

Saves changes to the template object the end-user enacted on the 'Add'
screen, then checks in.
The user is sent to 'My Workspace' if save succeeds and back to the 'Add'
screen if it fails.

=cut

sub add_checkin {
    my $self     = shift;
    my $q        = $self->query();
    my $template = $session{template};
    croak("No object in session") unless ref $template;

    # update template with CGI values
    $self->update_template($template) || return $self->redirect_to_workspace;

    # validate
    my %errors = $self->validate($template);
    return $self->add(%errors) if %errors;

    # save
    %errors = $self->_save($template);
    return $self->add(%errors) if %errors;

    $template->checkin;

    # clear template object from session
    delete $session{template};

    # return to workspace with message
    add_message('checkin_template', id => $template->template_id);
    $self->redirect_to_workspace;
}

=item add_save

Saves changes to the template object the end-user enacted on the 'Add' screen.
The user is sent to 'My Workspace' if save succeeds and back to the 'Add'
screen if it fails.

=cut

sub add_save {
    my $self     = shift;
    my $q        = $self->query();
    my $template = $session{template};
    croak("No object in session") unless ref $template;

    # update template with CGI values
    $self->update_template($template) || return $self->redirect_to_workspace;

    # validate
    my %errors = $self->validate($template);
    return $self->add(%errors) if %errors;

    # save
    %errors = $self->_save($template);
    return $self->add(%errors) if %errors;

    # checkout
    $template->checkout;

    # clear template object from session
    delete $session{template};

    # return to workspace with message
    add_message('message_saved');
    $self->redirect_to_workspace;
}

=item add_save_stay

Validates changes to the template from the 'Add' screen, saves the updated
object to the database, and redirects to the 'Edit' screen.

=cut

sub add_save_stay {
    my $self     = shift;
    my $q        = $self->query();
    my $template = $session{template};
    croak("No object in session") unless ref $template;

    # update template with CGI values
    $self->update_template($template) || return $self->redirect_to_workspace;

    # validate
    my %errors = $self->validate($template);
    return $self->add(%errors) if %errors;

    # save
    %errors = $self->_save($template);
    return $self->add(%errors) if %errors;

    # checkout
    $template->checkout;

    add_message('message_saved');

    # Redirect to edit
    my $url = $q->url(-relative => 1);
    $url .= "?rm=edit&template_id=" . $template->template_id();
    $self->header_props(-uri => $url);
    $self->header_type('redirect');
    return "Redirect: <a href=\"$url\">$url</a>";
}

=item advanced_search

The find mode allows the user to run an "advanced search" on
template objects, which will be listed on a paging view.

From this paging view the user may choose to edit or view
an object, or select a set of objects to be deleted.

This method is deperecated, left here for backwards compatibility.

=cut

sub advanced_search {
    my $self = shift;

    $self->query->param('do_advanced_search' => 1);

    return $self->search;
}

=item checkin_selected

Checkin all the templates which were checked on the list_active screen.

=cut

sub checkin_selected {
    my $self                  = shift;
    my $q                     = $self->query();
    my @template_checkin_list = ($q->param('krang_pager_rows_checked'));
    $q->delete('krang_pager_rows_checked');

    foreach my $template_id (@template_checkin_list) {
        my ($m) = pkg('Template')->find(template_id => $template_id);
        $m->checkin();
    }

    if (scalar(@template_checkin_list)) {
        add_message('selected_template_checkin');
    }
    return $self->list_active;
}

=item checkout_and_edit

Checks out the template object identified by template_id and sends the user
to edit.

=cut

sub checkout_and_edit {
    my $self = shift;
    my $q    = $self->query();

    my $template_id = $q->param('template_id');
    croak("Missing required template_id parameter.") unless $template_id;

    my ($t) = pkg('Template')->find(template_id => $template_id);
    croak("Unable to load template_id '$template_id'") unless $t;

    $t->checkout;
    return $self->edit;
}

=item delete

Deletes a template object from the 'Edit' screen.  The user is sent back to the
'search' mode afterwards.

The mode expects the query parameter 'template_id'.

=cut

sub delete {
    my $self        = shift;
    my $q           = $self->query();
    my $template_id = $q->param('template_id');

    eval { pkg('Template')->delete($template_id) };
    if ($@) {
        if (ref $@ && $@->isa('Krang::Template::Checkout')) {
            critical("Unable to delete template id '$template_id': $@");
            add_alert('error_deletion_failure', template_id => 'template_id');
        } else {
            croak($@);
        }
    } else {
        add_message('message_deleted');
    }

    return $self->search();
}

=item delete_selected

Deletes template objects selected from the 'search' screen and returns to
'search'.  If the object associated with a particular template_id cannot be
deleted, the user is returned to 'search' screen with an error message.

This mode expects the 'krang_pager_rows_checked' query param to contain the ids
of the objects to be deleted.  If none are passed, the user is returned to
the 'search' screen.

=cut

sub delete_selected {
    my $self = shift;
    my $q    = $self->query();

    my @template_ids = $q->param('krang_pager_rows_checked');

    return $self->search unless @template_ids;

    my @bad_ids;
    for my $t (@template_ids) {
        debug(__PACKAGE__ . ": attempting to delete template id '$t'.");
        eval { pkg('Template')->trash(template_id => $t); };
        if ($@) {
            if (ref $@ && $@->isa('Krang::Template::Checkout')) {
                critical("Unable to delete template id '$t': $@");
                push @bad_ids, $t;
            } else {
                croak($@);
            }
        }
    }

    if (@bad_ids) {
        add_alert('error_deletion_failure', template_id => join(", ", @bad_ids));
    } else {
        add_message('message_selected_deleted');
    }

    return $q->param('retired') ? $self->list_retired : $self->search;
}

=item deploy

Saves, deploys and checks in template.  Redirects to My Workspace.

=cut

sub deploy {
    my $self  = shift;
    my $query = $self->query;

    my $obj = $session{template};
    croak("No object in session") unless ref $obj;

    # update template with CGI values
    $self->update_template($obj) || return $self->redirect_to_workspace;

    if ($obj->template_id) {
        my %errors = $self->validate($obj);
        return $self->edit(%errors) if %errors;

        %errors = $self->_save($obj);
        return $self->edit(%errors) if %errors;
    } else {
        my %errors = $self->validate($obj);
        return $self->add(%errors) if %errors;

        %errors = $self->_save($obj);
        return $self->add(%errors) if %errors;
    }

    add_message('message_saved');

    my $publisher = pkg('Publisher')->new();
    $publisher->deploy_template(template => $obj);
    $obj->checkin;

    # clear template object from session
    delete $session{template};

    # Redirect to workspace with message
    add_message('deployed', id => $obj->template_id);
    $self->redirect_to_workspace;
}

=item deploy_selected

Deploys selected templates from the find interface.

=cut

sub deploy_selected {
    my $self = shift;
    my $q    = $self->query;

    my @template_ids = $q->param('krang_pager_rows_checked');

    return $self->search unless @template_ids;

    for my $t (@template_ids) {
        my $template = (pkg('Template')->find(template_id => $t))[0];
        $template->deploy;
        add_message('deployed', id => $template->template_id);
    }

    return $self->search;

}

=item edit

Displays the properties of a template object and allows the user to modify the
writable fields of the object.

This runmode expects the query parameter 'template_id'.

=cut

sub edit {
    my $self        = shift;
    my %args        = @_;
    my $q           = $self->query();
    my $template_id = $q->param('template_id');
    my $template    = $session{template};

    if ($template_id) {
        ($template) = pkg('Template')->find(template_id => $template_id);
        $session{template} = $template;
    }
    croak("No template object.") unless ref $template;

    my $t = $self->load_tmpl("edit.tmpl", associate => $q,);

    $t->param(%args) if %args;

    $t->param($self->get_tmpl_params($template));

    return $t->output();
}

=item edit_cancel

Cancels edit of template object on "Edit" screen and returns to 'search' run
mode.

=cut

sub edit_cancel {
    my $self = shift;

    my $q = $self->query();

    add_message('message_edit_cancelled');

    delete $session{template};

    return $self->search();
}

=item edit_checkin
Saves changes to the template object the end-user enacted on the 'Edit' screen,
then checks in.  The user is sent to 'My Workspace' if save succeeds and back
to the 'Edit' screen if it fails.

=cut

sub edit_checkin {
    my $self     = shift;
    my $q        = $self->query();
    my $template = $session{template};
    croak("No object in session") unless ref $template;

    # update template with CGI values
    $self->update_template($template) || return $self->redirect_to_workspace;

    # validate
    my %errors = $self->validate($template);
    return $self->edit(%errors) if %errors;

    # save
    %errors = $self->_save($template);
    return $self->edit(%errors) if %errors;

    $template->checkin;

    # clear template object from session
    delete $session{template};

    # Redirect to workspace with message
    add_message('checkin_template', id => $template->template_id);
    $self->redirect_to_workspace;
}

=item edit_save

Saves changes to the template object the end-user enacted on the 'Edit' screen.
The user is sent to 'My Workspace' if save succeeds and back to the 'Edit'
screen if it fails.

=cut

sub edit_save {
    my $self     = shift;
    my $q        = $self->query();
    my $template = $session{template};

    croak("No object in session") unless ref $template;

    # update template with CGI values
    $self->update_template($template) || return $self->redirect_to_workspace;

    # validate
    my %errors = $self->validate($template);
    return $self->edit(%errors) if %errors;

    # save
    %errors = $self->_save($template);
    return $self->edit(%errors) if %errors;

    # clear template object from session
    delete $session{template};

    # Redirect to workspace with message
    add_message('message_saved');
    $self->redirect_to_workspace;
}

=item edit_save_stay

Validates changes to the template from the 'Edit' screen, saves the updated
object to the database, and redirects to the 'Edit' screen.

=cut

sub edit_save_stay {
    my $self     = shift;
    my $q        = $self->query();
    my $template = $session{template};
    croak("No object in session") unless ref $template;

    # update template with CGI values
    $self->update_template($template) || return $self->redirect_to_workspace;

    # validate
    my %errors = $self->validate($template);
    return $self->edit(%errors) if %errors;

    # save
    %errors = $self->_save($template);
    return $self->edit(%errors) if %errors;

    add_message('message_saved');

    # Redirect to edit
    my $url = $q->url(-relative => 1);
    $url .= "?rm=edit&template_id=" . $template->template_id();
    $self->header_props(-uri => $url);
    $self->header_type('redirect');
    return "Redirect: <a href=\"$url\">$url</a>";
}

=item revert_version

Reverts the template to a prior incarnation then redirects to the 'Edit'
screen.

=cut

sub revert_version {
    my $self             = shift;
    my $q                = $self->query();
    my $selected_version = $q->param('selected_version');

    croak("Invalid selected version '$selected_version'")
      unless ($selected_version and $selected_version =~ /^\d+$/);

    # Perform revert
    my $template = $session{template};
    $template->revert($selected_version);
    $session{template} = $template;

    # Inform user
    add_message("message_revert_version", version => $selected_version);

    # Redirect to edit
    $q->delete_all();
    return $self->edit;
}

=item save_and_view_log

The purpose of this mode is to hand the user off to the log viewng
screen.  This mode writes changes back to the template object without
calling save().  When done, it performs an HTTP redirect to
history.pl.

=cut

sub save_and_view_log {
    my $self = shift;

    my $q = $self->query();

    # Update template object
    my $template = $session{template};
    $self->update_template($template) || return $self->redirect_to_workspace;
    my $id = $template->template_id;

    # Redirect to associate screen
    my $url =
        "history.pl?history_return_script=template.pl"
      . "&history_return_params=rm&history_return_params=edit"
      . "&id=$id&class=Template&id_meth=template_id";
    $self->header_props(-uri => $url);
    $self->header_type('redirect');
    return "Redirect: <a href=\"$url\">$url</a>";
}

=item view_log

The purpose of this mode is to hand the user off to the log viewng
screen to view the template in question.

=cut

sub view_log {
    my $self      = shift;
    my $q         = $self->query();
    my $id        = $q->param('template_id');
    my $return_rm = $q->param('return_rm');

    # Redirect to associate screen
    my $url =
        "history.pl?history_return_script=template.pl"
      . "&history_return_params=rm&history_return_params=$return_rm"
      . "&history_return_params=template_id&history_return_params=$id"
      . "&id=$id&class=Template&id_meth=template_id";
    $self->header_props(-uri => $url);
    $self->header_type('redirect');
    return "Redirect: <a href=\"$url\">$url</a>";
}

=item search

Displays a list of live Template objects based on the passed search criteria.  If no
criteria are passed, a list of all templates on the system are returned.  As a
simple search, the 'element', 'site', and 'url' fields are searched.

The run mode accepts the parameter "search_filter" which is used to perform
simple searches.

From this paging view the user may choose to view, edit or retire an
object, or select a set of objects to be deployed or deleted
(depending on the user's permission set).

=cut

sub search {
    my $self = shift;

    $self->query->param('other_search_place' => 'Search in Retired');

    my %args = (
        tmpl_file         => 'list_view.tmpl',
        include_in_search => 'live'
    );

    $self->_do_search(%args);
}

=item list_retired

Displays a list of retired Template objects based on the passed
search criteria.  If no criteria are passed, a list of all templates
on the system are returned.  As a simple search, the 'element',
'site', and 'url' fields are searched.

The run mode accepts the parameter "search_filter" which is used to perform
simple searches.

From this paging view the user may choose to view or unretire an
object, or select a set of objects to be deleted (depending on the
user's permission set).

=cut

sub list_retired {
    my $self = shift;

    $self->query->param('other_search_place' => 'Search in Live');

    my %args = (
        tmpl_file         => 'list_retired.tmpl',
        include_in_search => 'retired'
    );

    $self->_do_search(%args);
}

#
# Dispatches to _do_simple_search() or do_advanced_search().
#
sub _do_search {
    my ($self, %args) = @_;

    my $q = $self->query;

    # Search mode
    my $do_advanced_search =
      defined($q->param('do_advanced_search'))
      ? $q->param('do_advanced_search')
      : $session{KRANG_PERSIST}{pkg('Template')}{do_advanced_search};

    return $do_advanced_search
      ? $self->_do_advanced_search(%args)
      : $self->_do_simple_search(%args);
}

#
# The workhorse doing simple finds.
#
sub _do_simple_search {
    my ($self, %args) = @_;
    my $q = $self->query();

    my $t = $self->load_tmpl(
        $args{tmpl_file},
        associate         => $q,
        loop_context_vars => 1
    );

    my %user_permissions = (pkg('Group')->user_asset_permissions);
    $t->param(read_only => ($user_permissions{template} eq 'read-only'));

    $t->param(history_return_params => $self->make_history_return_params(@history_param_list));

    my $search_filter =
      defined($q->param('search_filter'))
      ? $q->param('search_filter')
      : $session{KRANG_PERSIST}{pkg('Template')}{search_filter};

    # ensure that $search_filter is at the very least defined.
    $search_filter = '' unless ($search_filter);

    # search in Retired or in Live?
    my $include = $args{include_in_search};

    # find retired stories?
    my $retired = $include eq 'retired' ? 1 : 0;

    # find live or retired stories?
    my %include_options = $retired ? (include_live => 0, include_retired => 1) : ();

    my $find_params = {simple_search => $search_filter, may_see => 1, %include_options};
    my $persist_vars = {
        rm => ($retired ? 'list_retired' : 'search'),
        search_filter      => $search_filter,
        $include           => 1,
        do_advanced_search => 0,
    };

    # setup pager
    my $pager = $self->make_pager($persist_vars, $find_params, $retired);
    my $pager_tmpl = $self->load_tmpl(
        'list_view_pager.tmpl',
        associate         => $q,
        loop_context_vars => 1,
        global_vars       => 1,
        die_on_bad_params => 0,
    );
    $pager->fill_template($pager_tmpl);

    # get pager output
    $t->param(pager_html => $pager_tmpl->output());

    # get counter params
    $t->param(row_count => $pager->row_count());

    $t->param(search_filter => $search_filter);

    return $t->output();
}

#
# The workhorse doing advanced finds.
#
sub _do_advanced_search {
    my ($self, %args) = @_;

    my $q = $self->query();
    my $t = $self->load_tmpl($args{tmpl_file}, associate => $q);

    my %user_permissions = (pkg('Group')->user_asset_permissions);
    $t->param(read_only => ($user_permissions{template} eq 'read-only'));

    # if the user clicked 'clear', nuke the cached params in the session.
    if (defined($q->param('clear_search_form'))) {
        delete $session{KRANG_PERSIST}{pkg('Template')};
    }

    $t->param(do_advanced_search    => 1);
    $t->param(history_return_params => $self->make_history_return_params(@history_param_list));

    # search in Retired or in Live?
    my $include = $args{include_in_search};

    # find retired stories?
    my $retired = $include eq 'retired' ? 1 : 0;

    # find live or retired stories?
    my %include_options = $retired ? (include_live => 0, include_retired => 1) : ();

    my $find_params = \%include_options;

    my $persist_vars = {
        rm => ($retired ? 'list_retired' : 'search'),
        do_advanced_search => 1,
        $include           => 1,
    };

    # Build find params
    my $search_below_category_id =
      defined($q->param('search_below_category_id'))
      ? $q->param('search_below_category_id')
      : $session{KRANG_PERSIST}{pkg('Template')}
      {cat_chooser_id_template_search_form_search_below_category_id};
    if ($search_below_category_id) {
        $persist_vars->{search_below_category_id} = $search_below_category_id;
        $find_params->{below_category_id}         = $search_below_category_id;
    }

    # search_element
    my $search_element =
      defined($q->param('search_element'))
      ? $q->param('search_element')
      : $session{KRANG_PERSIST}{pkg('Template')}{search_element};

    if ($search_element) {
        $find_params->{filename}        = "$search_element.tmpl";
        $persist_vars->{search_element} = $q->param('search_element');
    }

    # search_template_id
    my $search_template_id =
      defined($q->param('search_template_id'))
      ? $q->param('search_template_id')
      : $session{KRANG_PERSIST}{pkg('Template')}{search_template_id};

    if ($search_template_id) {
        $find_params->{template_id}         = $search_template_id;
        $persist_vars->{search_template_id} = $q->param('search_template_id');
        $t->param(search_template_id => $search_template_id);
    }

    # search_url
    my $search_url =
      defined($q->param('search_url'))
      ? $q->param('search_url')
      : $session{KRANG_PERSIST}{pkg('Template')}{search_url};

    if ($search_url) {
        $find_params->{url_like}    = "%$search_url%";
        $persist_vars->{search_url} = $q->param('search_url');
        $t->param(search_url => $search_url);
    }

    # Run pager
    my $pager = $self->make_pager($persist_vars, $find_params, $retired);
    my $pager_tmpl = $self->load_tmpl(
        'list_view_pager.tmpl',
        associate         => $q,
        loop_context_vars => 1,
        global_vars       => 1,
        die_on_bad_params => 0,
    );
    $pager->fill_template($pager_tmpl);

    $t->param(pager_html => $pager_tmpl->output());
    $t->param(row_count  => $pager->row_count());

    # Set up element chooser
    $t->param(
        element_chooser => scalar template_chooser(
            query      => $q,
            name       => 'search_element',
            formname   => 'template_search_form',
            persistkey => 'Element',
        )
    );

    # Set up category chooser
    $t->param(
        category_chooser => scalar category_chooser(
            query      => $q,
            formname   => 'template_search_form',
            persistkey => pkg('Template'),
            name       => 'search_below_category_id',
        )
    );
    return $t->output();
}

=item view

View the attributes of the template object.

=cut

sub view {
    my $self        = shift;
    my $version     = shift;
    my $q           = $self->query();
    my $t           = $self->load_tmpl('view.tmpl', die_on_bad_params => 0);
    my $template_id = $q->param('template_id')
      || croak("No 'template_id' specified.");
    my %find;

    $find{template_id} = $template_id;

    if ($version) {
        $find{version} = $version;
        $t->param(is_old_version => 1);
    }
    my ($template) = pkg('Template')->find(%find);
    croak("Can't find template with template_id '$template_id'.")
      unless ref $template;

    $t->param($self->get_tmpl_params($template));

    return $t->output();
}

=item view_version

Display the specified version of the template object in a view form.

=cut

sub view_version {
    my $self             = shift;
    my $q                = $self->query();
    my $selected_version = $q->param('selected_version');

    die("Invalid selected version '$selected_version'")
      unless ($selected_version and $selected_version =~ /^\d+$/);

    # Update template object
    my $template = $session{template};
    $self->update_template($template) || return $self->redirect_to_workspace;

    # Return view mode with version
    return $self->view($selected_version);
}

=item list_active

List all active templates.  Provide links to view each template.  If the
user has 'checkin all' admin abilities then checkboxes are provided to
allow the template to be checked-in.

=cut

sub list_active {
    my $self = shift;
    my $q    = $self->query();

    # Set up persist_vars for pager
    my %persist_vars = (rm => 'list_active');

    # Set up find_params for pager
    my %find_params = (checked_out => 1, may_see => 1);

    # may checkin all ?
    my %admin_perms     = pkg('Group')->user_admin_permissions();
    my $may_checkin_all = $admin_perms{may_checkin_all};

    my $pager = pkg('HTMLPager')->new(
        cgi_query    => $q,
        persist_vars => \%persist_vars,
        use_module   => pkg('Template'),
        find_params  => \%find_params,
        columns      => [
            (
                qw(
                  template_id
                  filename
                  url
                  user
                  commands_column
                  )
            ),
            ($may_checkin_all ? ('checkbox_column') : ())
        ],
        column_labels => {
            template_id     => 'ID',
            filename        => 'File Name',
            url             => 'URL',
            user            => 'User',
            commands_column => '',
        },
        columns_sortable => [qw( template_id filename url )],
        row_handler      => sub { $self->list_active_row_handler(@_); },
        id_handler       => sub { return $_[0]->template_id },
    );

    my $pager_tmpl = $self->load_tmpl(
        'list_active_pager.tmpl',
        die_on_bad_params => 0,
        loop_context_vars => 1,
        global_vars       => 1,
        associate         => $q,
    );
    $pager->fill_template($pager_tmpl);

    # Set up output
    my $template = $self->load_tmpl('list_active.tmpl', associate => $q);
    $template->param(
        pager_html            => $pager_tmpl->output,
        row_count             => $pager->row_count,
        may_checkin_all       => $may_checkin_all,
    );
    return $template->output;
}

#############################
#####  PRIVATE METHODS  #####
#############################

# Construct param hashref to be used for edit template output
sub get_tmpl_params {
    my $self     = shift;
    my $template = shift;
    my $q        = $self->query();
    my @fields   = qw/content filename template_id testing url
      version deployed_version/;
    my $rm = $q->param('rm');
    my (%tmpl_params, $version);

    # loop through template fields
    $tmpl_params{$_} = ($template->$_ || '') for @fields;
    debug("FILENAME: $tmpl_params{filename}");
    $version = $template->version;

    if ($q->param('add_mode')) {

        $tmpl_params{element_chooser} = template_chooser(
            query    => $q,
            name     => 'element_class_name',
            formname => 'edit_template_form',
            onchange => 'update_filename(field)',
        );

        $q->delete('element_class_name');

    }

    unless ($rm =~ /^view/) {

        # make sure category_id is set for category chooser
        $q->param('category_id', $template->category_id);

        $tmpl_params{category_chooser} = category_chooser(
            query    => $q,
            name     => 'category_id',
            formname => 'edit_template_form',
            may_edit => 1,
        );

        # we don't need it anymore
        $q->delete('category_id');

        $tmpl_params{upload_chooser} = $q->filefield(
            -name => 'template_file',
            -size => 32
        );
        $tmpl_params{version_chooser} = $q->popup_menu(
            -name     => 'selected_version',
            -values   => $template->all_versions,
            -default  => $version,
            -override => 1
        );
        $tmpl_params{history_return_params} = $self->make_history_return_params('rm');
    } else {
        my %history_hash = $q->param('history_return_params');
        my @history_params;
        while (my ($k, $v) = each %history_hash) {
            push @history_params,
              $q->hidden(
                -name     => $k,
                -value    => $v,
                -override => 1
              );
            $tmpl_params{was_edit} = 1
              if (($k eq 'rm') && ($v eq 'checkout_and_edit'));
        }
        $tmpl_params{history_return_params} = join("\n", @history_params);

        $tmpl_params{can_edit} = 1
          unless (
            not($template->may_edit)
            or ($template->checked_out
                and ($template->checked_out_by ne $ENV{REMOTE_USER}))
            or $template->retired
            or $template->trashed
          );

        $tmpl_params{return_script} = $q->param('return_script');
    }

    return \%tmpl_params;
}

# Given an array of parameter names, return HTML hidden
# input fields suitible for setting up a return link
sub make_history_return_params {
    my $self                      = shift;
    my @history_return_param_list = (@_);

    my $q = $self->query();

    my @history_return_params_hidden = ();
    foreach my $hrp (@history_return_param_list) {

        # Store param name
        push(
            @history_return_params_hidden,
            $q->hidden(
                -name     => 'history_return_params',
                -value    => $hrp,
                -override => 1
            )
        );

        # Store param value
        my $pval = $q->param($hrp);
        $pval = '' unless (defined($pval));
        push(
            @history_return_params_hidden,
            $q->hidden(
                -name     => 'history_return_params',
                -value    => $pval,
                -override => 1
            )
        );
    }

    my $history_return_params = join("\n", @history_return_params_hidden);
    return $history_return_params;
}

# Given a persist_vars and find_params, return the pager object
sub make_pager {
    my $self = shift;
    my ($persist_vars, $find_params, $retired) = @_;

    my %user_permissions = (pkg('Group')->user_asset_permissions);

    my @columns = qw(deployed
      template_id
      filename
      url
      commands_column
      status);
    push @columns, 'checkbox_column'
      unless ($user_permissions{template} eq 'read-only');

    my %column_labels = (
        deployed        => '',
        template_id     => 'ID',
        filename        => 'File Name',
        url             => 'URL',
        commands_column => '',
        status          => 'Status',
    );

    my $q     = $self->query();
    my $pager = pkg('HTMLPager')->new(
        cgi_query        => $q,
        persist_vars     => $persist_vars,
        use_module       => pkg('Template'),
        find_params      => $find_params,
        columns          => \@columns,
        column_labels    => \%column_labels,
        columns_sortable => ['template_id', 'filename', 'url',],
        row_handler      => sub { $self->search_row_handler(@_, retired => $retired) },
        id_handler => sub { return $_[0]->template_id },
    );

    return $pager;
}

# Handles rows for search run mode
sub search_row_handler {
    my ($self, $row, $template, $pager, %args) = @_;

    my $list_retired        = $args{retired};
    my $may_edit_and_retire = (
        not($template->may_edit)
          or (  ($template->checked_out)
            and ($template->checked_out_by ne $ENV{REMOTE_USER}))
    ) ? 0 : 1;

    $row->{filename}    = $template->filename;
    $row->{template_id} = $template->template_id;
    $row->{url}         = format_url(url => $template->url, length => 30);

    # Buttons: all may view
    $row->{commands_column} =
        qq|<input value="View Detail" onclick="view_template('|
      . $template->template_id
      . qq|')" type="button" class="button">|;

    # short-circuit for trashed template
    if ($template->trashed) {
        $row->{status}          = 'Trash';
        $row->{checkbox_column} = "&nbsp;";
        return 1;
    }

    # Buttons and status continued
    if ($list_retired) {

        # Retired Template screen
        if ($template->retired) {
            $row->{commands_column} .= ' '
              . qq|<input value="Unretire" onclick="unretire_template('|
              . $template->template_id
              . qq|')" type="button" class="button">|
              if $may_edit_and_retire;
            $row->{deployed} = '';
            $row->{status}   = '&nbsp;';
        } else {
            if ($template->checked_out) {
                $row->{status} = "Live <br/> Checked out by <b>"
                  . (pkg('User')->find(user_id => $template->checked_out_by))[0]->login . '</b>';
            } else {
                $row->{status} = 'Live';
            }
            $row->{deployed} = $template->deployed ? '<b>D</b>' : '&nbsp;';
        }
    } else {

        # Find Template screen
        if ($template->retired) {

            # Template is retired
            $row->{deployed}        = '';
            $row->{status}          = 'Retired';
            $row->{checkbox_column} = "&nbsp;";
        } else {

            # Template is not retired: Maybe we may edit and retire
            $row->{commands_column} .= ' '
              . qq|<input value="Edit" onclick="edit_template('|
              . $template->template_id
              . qq|')" type="button" class="button">| . ' '
              . qq|<input value="Retire" onclick="retire_template('|
              . $template->template_id
              . qq|')" type="button" class="button">|
              if $may_edit_and_retire;
            if ($template->checked_out) {
                $row->{status} = "Checked out by <b>"
                  . (pkg('User')->find(user_id => $template->checked_out_by))[0]->login . '</b>';
            } else {
                $row->{status} = '&nbsp;';
            }
            $row->{deployed} = $template->deployed ? '<b>D</b>' : '&nbsp;';
        }
    }

    unless ($may_edit_and_retire) {
        $row->{checkbox_column} = "&nbsp;";
    }
}

# Updates object with CGI param values
sub update_template {
    my $self     = shift;
    my $template = shift;
    my $q        = $self->query();

    # make sure template is still checked out to us (and hasn't been saved in another window)
    if (my $id = $template->template_id) {
        if (my ($template_in_db) = pkg('Template')->find(template_id => $id)) {
            if (  !$template_in_db->checked_out
                || $template_in_db->checked_out_by ne $ENV{REMOTE_USER}
                || $template_in_db->version > $template->version)
            {
                add_alert('template_modified_elsewhere', id => $id);
                delete $session{template};
                return 0;
            }
        } else {
            add_alert('template_deleted_elsewhere', id => $id);
            delete $session{template};
            return 0;
        }
    }

    # we're safe to continue...
    for (qw/category_id content filename/) {
        next if ($_ eq 'filename')    && $template->template_id;
        next if ($_ eq 'category_id') && $template->template_id;

        my $val = $q->param($_) || '';
        if (($_ eq 'content')) {
            if (my $fh = $q->upload('template_file')) {
                my ($buffer, $content);
                $content .= $buffer while (read($fh, $buffer, 10240));
                $template->$_($content);
                $q->delete('template_file');
            } else {
                $template->$_($val);
            }
        } elsif ($_ eq 'category_id') {
            if ($val eq '') {

                # clear the category, none selected
                $template->category_id(undef);
            } else {
                $template->category_id($val);
            }
        } else {
            $template->{filename} = $val;
        }
        $q->delete($_);
    }

    if ($q->param('testing')) {
        $template->mark_for_testing;
    } else {
        $template->unmark_for_testing;
    }

    return 1;    # success
}

# Validates input from the CGI
sub validate {
    my ($self, $template) = @_;
    my $q = $self->query();
    my %errors;

    unless ($template->template_id) {

        # validate category_id
        my $category_id = $template->category_id || 0;
        $errors{error_invalid_category_id} = 1
          unless $category_id =~ /^\d+$/;

        my $filename = $template->filename || '';

        # see if filename is set
        $errors{error_no_filename} = 1
          unless $filename;

        # check for a valid filename
        $errors{error_invalid_filename} = 1
          unless $filename =~ /^[-\w]+\.tmpl$/;
    }

    add_alert($_) for keys %errors;
    $q->param('errors', 1) if keys %errors;

    return %errors;
}

# does the actual saving of the object to the DB
sub _save {
    my ($self, $template) = @_;
    my $q = $self->query();

    eval { $template->save };

    if ($@) {
        if (ref($@) && $@->isa('Krang::Template::DuplicateURL')) {
            add_alert('duplicate_url', url => $template->url);
            $q->param('errors', 1);
            return (duplicate_url => 1);
        } elsif (ref($@) && $@->isa('Krang::Template::NoCategoryEditAccess')) {
            my $category_id = $@->category_id;
            my ($category) = pkg('Category')->find(category_id => $category_id);
            croak("Can't load category_id '$category_id'")
              unless (ref($category));
            add_alert(
                'error_no_category_access',
                url    => $category->url,
                cat_id => $category_id
            );
            $q->param('errors', 1);
            return (error_category_id => 1);
        } else {
            croak($@);
        }
    }

    return ();
}

# Pager row handler for template list active run-mode
sub list_active_row_handler {
    my $self = shift;
    my $q    = $self->query;
    my ($row, $template, $pager) = @_;

    # Columns:
    #

    # template_id
    $row->{template_id} = $template->template_id();

    # format url to fit on the screen and to link to preview
    $row->{url} = format_url(url => $template->url());

    # filename
    $row->{filename} = $q->escapeHTML($template->filename);

    # commands column
    $row->{commands_column} =
        qq|<input value="View Detail" onclick="view_template('|
      . $template->template_id
      . qq|')" type="button" class="button">|;

    # user
    my ($user) = pkg('User')->find(user_id => $template->checked_out_by);
    $row->{user} = $q->escapeHTML($user->first_name . " " . $user->last_name);
}

sub autocomplete {
    my $self = shift;
    return autocomplete_values(
        table  => 'template',
        fields => [qw(template_id element_class_name filename)],
    );
}

sub template_chooser_node {
    my $self    = shift;
    my $query   = $self->query();
    my $chooser = template_chooser_object(query => $query,);
    return $chooser->handle_get_node(query => $query);
}

=item retire

Move template to the retire and return to the Find Template screen

=cut

sub retire {
    my $self = shift;
    my $q    = $self->query;

    my $template_id = $q->param('template_id');

    croak("No template_id found in CGI params when archiving template.")
      unless $template_id;

    # load template from DB and retire it
    my ($template) = pkg('Template')->find(template_id => $template_id);

    croak("Unable to load Template '" . $template_id . "'.")
      unless $template;

    $template->retire();

    add_message('template_retired', id => $template_id, url => $template->url);

    $q->delete('template_id');

    return $self->search();
}

=item unretire

Move template from retire back to live. If a DuplicateURL conflict
occurs, leave the template retired and alert the user.

=cut

sub unretire {
    my $self = shift;
    my $q    = $self->query;

    my $template_id = $q->param('template_id');

    croak("No template_id found in CGI params when trying to unretire template.")
      unless $template_id;

    # load template from DB and unretire it
    my ($template) = pkg('Template')->find(template_id => $template_id);

    croak("Unable to load template '" . $template_id . "'.")
      unless $template;

    eval { $template->unretire() };

    if ($@ and ref($@)) {
        if ($@->isa('Krang::Template::DuplicateURL')) {
            add_alert(
                'duplicate_url_on_unretire',
                id       => $template_id,
                other_id => $@->template_id,
                url      => $template->url
            );
        } elsif ($@->isa('Krang::Template::NoEditAccess')) {

            # param tampering
##	    return $self->access_forbidden();
            # or perhaps a permission change
            add_alert('access_denied_on_unretire', id => $template_id, url => $template->url);
        }
        return $self->list_retired;
    }

    add_message('template_unretired', id => $template_id, url => $template->url);

    return $self->list_retired;

}

=back

=cut

1;
