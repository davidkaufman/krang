package PBMM::double_cover_column;
use strict;
use warnings;

=head1 NAME

PBMM::double_cover_column

=head1 DESCRIPTION

PBMM double cover column (uses cover_column) element class for Krang. 

=cut


use base 'Krang::ElementClass';

sub new {
   my $pkg = shift;
   my %args = ( name => 'double_cover_column',
                children => 
                [ 
                  PBMM::cover_column->new(   name => "left_column",
                                                allow_delete => '0',
                                                    display_name => 'Left Column',
                                                    min => 1,
                                                    max => 1 ),
                PBMM::cover_column->new(   name => "right_column",
                                                allow_delete => '0',
                                                    display_name => 'Right Column',
                                                    min => 1,
                                                    max => 1 ),
                ],
                @_);
   return $pkg->SUPER::new(%args);
}

1;
