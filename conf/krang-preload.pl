#!/usr/bin/perl -w

##########################################
####  MODULES TO PRE-LOAD INTO KRANG  ####
##########################################

# setup load paths
use Krang::ClassFactory qw(pkg);
use Krang::ClassLoader 'AddOn';
# call the init-handler of any Addons being used
BEGIN {
    print STDERR "Initializing AddOns...\n";
    pkg('AddOn')->call_handler('InitHandler');
}
use Krang::ClassLoader 'lib';
use Krang::ClassLoader Conf => qw(KrangRoot);
use File::Find qw(find);
use File::Spec::Functions qw(catdir);
use Krang::ClassLoader 'HTMLTemplate';


# load all Krang libs, with a few exceptions
my $skip = qr/Profiler|Test|BricLoader|Cache|FTP|DataSet|Upgrade|MethodMaker|Daemon|Script|XML|ClassLoader/;
find({ 
      wanted => sub {
          return unless m!(Krang/.*).pm$!;
          my $path = $1;
          return if /^\.?#/; # skip emacs droppings
          return if /$skip/;

          my $pkg = join('::', (split(/\//, $path)));
          eval "use $pkg;";
          die "Problem loading $pkg:\n\n$@" if $@;
      },
      no_chdir => 1
     },
     KrangRoot . '/lib/Krang');

# load all template
print STDERR "Pre-loading HTML Templates...\n";
find(
     sub {
         return if /^\.?#/;          # skip emacs droppings
         return if /\.base\.tmpl$/;  # skip base templates
         return unless /\.tmpl$/;    # only load localized templates
         pkg('HTMLTemplate')->new(
				   path     => $File::Find::dir,
				   filename => $_,
				   cache    => 1,
				   loop_context_vars => 1,
				  );
     },
     KrangRoot . '/templates');


print STDERR "Krang Pre-load complete.\n";

1;