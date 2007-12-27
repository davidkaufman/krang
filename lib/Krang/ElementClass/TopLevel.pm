package Krang::ElementClass::TopLevel;
use Krang::ClassFactory qw(pkg);
use strict;
use warnings;

use Carp qw(croak);
use Data::Dumper qw();

use Krang::ClassLoader Log => qw(debug info critical);
use Krang::ClassLoader base => 'ElementClass';

=head1 NAME

Krang::ElementClass::TopLevel - base class for top-level element classes

=head1 SYNOPSIS

  package ElementSet::article;
  use base 'Krang::ElementClass::TopLevel';

  # override new() to setup element class parameters
  sub new { 
      my $pkg = shift;
      my %arg = (name      => "article",
                 children  => [ 'deck', 'paragraph', 'image' ],
                 @_);
      return $pkg->SUPER::new(%arg); 
  }

  1;

=head1 DESCRIPTION

This class serves as the base class for top-level element classes.
The root of an element tree must start with a sub-class of this class.
The methods provided allow this special element to control some
aspects of the Story or Category which contains it.  For example, the
C<build_url> method allows element classes to determine how a story
builds its URL.

Additionally, some methods make no sense for a top-level element
class, and they are stubbed out with implementations that croak.  For
example, the C<input_form()> method is useless for a top-level element
because the UI does not allow top-level elements to recieve input.

=head1 INTERFACE

=over

=cut

# stub out interface methods that should never be called on a
# top-level object
BEGIN {
    no strict 'refs'; # needed for glob assign
    foreach my $meth (qw(input_form param_names bulk_edit_data 
                         bulk_edit_filter view_data validate 
                         load_query_data)) {
        *{"Krang::ElementClass::TopLevel::$meth"} = 
          sub { croak($meth .'() called on a top-level element!'); };
    }
}

=item C<< $url = $class->build_url(story => $story, category => $category) >>

Builds a URL for the given story and category.  The default
implementation takes the category url and appends a URI encoded copy
of the story slug.  This may be overriden by top level elements to
implement alternative URL schemes.  

=cut

sub build_url {
    my ($self, %arg) = @_;
    my ($story, $category) = @arg{qw(story category)};
    my $use_slug = ($story->slug && ($story->class->slug_use ne 'prohibit'));
    return ($category ? $category->url : '') . ($use_slug ? CGI::Util::escape($story->slug) : '');
}


=item C<< $url = $class->build_preview_url(story => $story, category => $category) >>

Builds a preview-path URL for the given story and category.  The
default implementation takes the category url and appends a URI
encoded copy of the story slug.  This may be overriden by top level
elements to implement alternative URL schemes.  See
L<Krang::ElementClass::Cover> for an example.

=cut

sub build_preview_url {
    my ($self, %arg) = @_;
    my ($story, $category) = @arg{qw(story category)};
    my $use_slug = ($story->slug && ($story->class->slug_use ne 'prohibit'));
    return ($category ? $category->preview_url : '') . ($use_slug ? CGI::Util::escape($story->slug) : '');
}


=item C<< @fields = $class->url_attributes() >>

Returns a list of Story attributes that are being used to compute the
url in build_url().  For example, the default implementation returns
('slug') unless slug_use() is set to 'prohibit'.

=cut

sub url_attributes { 
    my $self = shift;
    ($self->slug_use ne 'prohibit') ? ('slug') : ();
}

=item C<< @schedules = $class->default_schedules(element => $element, story_id ==> $story_id) >>

Called when a top-level object is created.  May return a list of
Krang::Schedule objects.  The default implementation returns and empty
list.

=cut

sub default_schedules { return (); }

=item C<< $file_name = $class->filename() >>

Returns the filename (independant of the extension) to be used when writing to disk data generated by this element tree.  Will return C<index> unless overridden.

=cut

sub filename {
    return 'index';
}

=item C<< $file_extension = $class->extension() >>

Returns the file extension (see filename()) to be used when writing to disk data generated by this element tree.  Will return C<.html> unless overridden.

=cut

sub extension {
    return '.html';
}

=item C<< $class->save_hook(element => $element) >>

Called just before the story/category containing the element tree is
saved.  The default implementation does nothing.

=cut

sub save_hook {}

=item C<< $class->delete_hook(element => $element) >>

Called just before the story/category containing the element tree is
deleted.  This routine can be used to do any necessary cleanup.  The
default implementation does nothing.

=cut

sub delete_hook {}

=item C<< $bool = $class->publish_check(element => $element) >>

This method is called before publishing the story via a scheduled
publish job (not in the UI).  If this method returns 0 (false) the
publish won't happen.  This may be used to implement a "Holding" desk
where stories won't be automatically published, for example.

The default implementation just returns 1 (true) in all cases.

=cut

sub publish_check { 1 }


=item C<< $bool = $class->force_republish(element => $element) >>

This method is called at the beginning of the publish process.  If
true, all other checks are ignored and the story is published.  If
false, other versioning and sanity checks (see L<Krang::Publisher> and
L<Krang::Story>) are made to determine whether or not to publish the
story.

The default implementation returns 0 (false) in all cases.

=cut

sub force_republish { 0 }


=item C<< $bool = $class->use_category_templates(element => $element) >>

This method is called during the publish/preview process.  If true, it
will wrap the story output with the output of the category templates
before writing the result to the filesystem.  If false, the story
output is the final output.

The default implementation returns 1 (true) in all cases.

=cut

sub use_category_templates { 1 }


=item C<< $bool = $class->publish_category_per_page(element => $element) >>

This method is called during the publish/preview process.  If true, it
will re-publish the category element for each page in the story,
passing the current page number and total number of pages to the
category element.  The published output will be matched only with the
current page.

If false, the category element will be published once, and its output
will be matched up with each story page.

The default implementation returns 0 (false) in all cases.

Override this method to return 1 (true) if you want to generate
content on category templates varies for each page in a story.

=cut

sub publish_category_per_page { 0 }

=item C<< $category_input = $class->category_input() >>

This method is used to determine whether the user needs
to select a category when creating a New Story.

  It returns 1 of 3 values:
  'require'  - user must specify category 
  'allow'    - user may specify category 
  'prohibit' - user may not specify category 

The default implementation returns 'require'.
 
=cut

sub category_input     { 
    return 'require'; 
}

=item C<< @category_ids = $class->auto_category_ids(cover_date => $cover_date,
                                                    slug => $slug,
                                                    title => $title); >>

This method auto-selects one or more category IDs based on cover_date, title, 
and/or slug. The default implementation simply returns the first category ID 
it can find.

=cut 

sub auto_category_ids {
    return (pkg('Category')->find(limit => 1, ids_only => 1))[0];
}

=item C<< $validate = $class->validate_category(category => $category,
                                                cover_date => $cover_date,
                                                slug => $slug,
                                                title => $title); >>

This method validates whether a given category is acceptable for a story
based on the story's cover_date, slug, and/or title. If so, it returns 1.
If not, it returns a text error that is passed onto the user.

The default implementation returns 1 in all cases.

=cut

sub validate_category  { 
    return 1;
}

=item C<< $slug_use = $class->slug_use() >>

This method is used to determine slug behavior.

  It returns 1 of 4 values:
  'require'    - slug is required
  'encourage'  - slug field is present in New Story CGI, but can be left empty
  'discourage' - slug field is initially greyed-out in New Story CGI
  'prohibit'   - slug is prohibited 

The default implementation returns 'encourage'.
 
=cut
    
sub slug_use {
    return 'encourage';
}


=item C<< $title_to_slug = $class->title_to_slug() >>

This method returns the Javascript necessary to dynamically convert a 
title to a slug in the New Story form. The default implementation returns 
nothing, causing the hard-coded Javascript to execute. If a particular story 
type requires a different approach, this method can be overridden in the 
story class. The Javascript returned should consist of an unnamed function, 
for example "function(title) { return title.toLowerCase }"

=cut

sub title_to_slug {
    return '';
}


=item C<< $bool = $class->hidden() >>

This method sets the value of C<< Krang::Story>->hidden() >>.  If
true, stories of this class will not return in a call to C<<
Krang::Story->find() >> unless the parameter C<< show_hidden => 1 >>
is set.

As an example: this is useful for story classes that aren't supposed
to show up in most-recently-published lists.  For example, the
HREF[Krang RSS|http://krang.sourceforge.net] and HREF[Krang
Sitemap|href://krang.sourceforge.net] addons republish nightly by
default - neither of these story classes should show up in a cover
displaying the most-recently-published stories.

This method is false by default.

=cut

sub hidden { 0 }

=item C<< $file_mode = $class->file_mode($filename) >>

This method supplies the mode for a given file being published.  The
default implementation return undef which leaves the file with the
default mode, determined by the process umask.

=cut

sub file_mode {}



=item publish_frontend_app_template()

  $self->publish_frontend_app_template(
      publisher         => $publisher,
      fill_with_element => $element,
      filename          => "search_results.tmpl",
      use_category      => 1,
      tmpl_data         => {Foo => 123, Bar => 456},
  );

This method is used to publish a template to the front-end of a website for 
use by a front-end CGI.  It is expected to be called from within the 
fill_template() or publish() methods.  This method takes the following 
parameters:

=over

=item publisher

The Krang::Publisher object.  This parameter is required.

=item filename

The name of the template file to publish.  The template will be located
via the category path as per Krang's normal template finding behavior.
This parameter is required.

=item output_filename

The name of the file that is published. If not given it will default
to C<filename>.

=item use_category

Set to "1" to wrap this template in the category template.  Defaults to
"0".

=item tmpl_data

If provided, this hashref will be used to populate any parameters in
the template.

=item fill_with_element

If supplied, this element will be used to populate the contents of
the template.  (In which case, the tmpl_data hashref will augment the
output of the fill_template() process.

=back

NOTE: Template vars, loops (etc.) which are needed by your front-end CGI 
should be named "<dyn_*>" instead of "<tmpl_*>", e.g.:

  <dyn_if some_boolean>
    <dyn_loop some_loop>
      <dyn_var foo1>
      <dyn_var foo2>
      <dyn_var foo3>
    </dyn_loop>
  </dyn_if>

This is to differentiate the template tags needed by the CGI from
those needed by the Krang publishing process.

=cut

sub publish_frontend_app_template {
    my $self = shift;
    my %args = @_;

    my $publisher = $args{publisher} || croak ("No publisher specified");
    my $filename = $args{filename} || croak("No filename specified");
    my $use_category = $args{use_category} || 0;
    my $tmpl_data = $args{tmpl_data} || 0;
    my $fill_with_element = $args{fill_with_element} || 0;
    my $output_filename = $args{output_filename} || $filename;

    # Find template or die trying
    my $tmpl = $self->find_template( filename  => $filename,
                                     publisher => $publisher );

    if ($fill_with_element) {
        $fill_with_element->class->fill_template
            ( tmpl => $tmpl,
              publisher => $publisher,
              element => $fill_with_element,
            );
    }

    # Put tmpl_data into template
    $tmpl->param(%$tmpl_data) if ($tmpl_data);

    # Convert <DYN_*> to <TMPL_*>
    my $html = $tmpl->output();
    $self->_post_process_html(\$html);

    # Publish the template
    debug("Publishing template '$filename'");
    $publisher->additional_content_block( filename => $output_filename,
                                          content => $html,
                                          use_category => $use_category );

}

sub _post_process_html {
    my ($self, $html_ref) = @_;

    # change tags for dynamic HTML::Template stuff
    if (defined $html_ref && defined $$html_ref) {
        $$html_ref =~ s|<DYN_|<TMPL_|gi;
        $$html_ref =~ s|</DYN_|</TMPL_|gi;
    }
}

=item publish_frontend_app_stub()

  $self->publish_frontend_app_stub(
      publisher  => $publisher,
      filename   => "myapp.pl",
      app_module => 'Foo::Bar::Baz',
      app_params => {Foo => 123, Bar => 456},
  );

Publish a CGI "instance script" which will invoke a CGI::Application-based
module.  This method takes the following parameters:

=over

=item * publisher

The Krang::Publisher object.  This parameter is required.

=item * filename

The name of the stub file to publish.  This file will be made executable
(mode 0755) so as to comply with mod_cgi, Apache::Registry, and
ModPerl::Registry This parameter is required.

=item * app_module

The CGI::Application based (or compatible) module which will be
instantiated via the application stub file.  This parameter is required.

=item * app_params

These parameters will be passed to the application and made available
via the $app->param() method.  (See the CGI::Application documentation.)

=item * return_only

If true, then the text of the resulting script won't be published to
the filesystem but will instead be returned. This is useful if you
want to return the output as part of your publish() method.
Defaults to false;

=back

=cut

sub publish_frontend_app_stub {
    my $self = shift;
    my %args = @_;

    my $publisher   = $args{publisher}  || croak("No publisher specified");
    my $filename    = $args{filename}   || croak("No filename specified");
    my $app_module  = $args{app_module} || croak("No app_module specified");
    my $app_params  = $args{app_params} || 0;
    my $return_only = $args{return_only};

    my $params_string = "";
    if ($app_params) {
        my $dumper = Data::Dumper->new([$app_params]);
        $dumper->Terse(1);
        $dumper->Indent(0);
        $params_string = "PARAMS => " . $dumper->Dump;
    }

    my $script = <<EOF;
#!/usr/bin/env perl
use strict;
use warnings;
use $app_module;
my \$app = $app_module->new($params_string);
\$app->run;
EOF
;

    unless( $return_only ) {
        debug("Publishing app stub '$filename'");
        $publisher->additional_content_block
            ( filename      => $filename, 
              content       => $script, 
              use_category  => 0,
              mode          => 0755,
            );    
    }
    return $script;
}



=back

=cut

1;