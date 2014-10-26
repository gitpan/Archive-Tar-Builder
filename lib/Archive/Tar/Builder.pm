package Archive::Tar::Builder;

# Copyright (c) 2012, cPanel, Inc.
# All rights reserved.
# http://cpanel.net/
#
# This is free software; you can redistribute it and/or modify it under the same
# terms as Perl itself.  See the LICENSE file for further details.

use strict;
use warnings;

use Exporter ();
use XSLoader ();

use Archive::Tar::Builder::UserCache ();

BEGIN {
    use vars qw(@ISA $VERSION);

    our @ISA     = qw(Exporter);
    our $VERSION = '0.9';
}

XSLoader::load( 'Archive::Tar::Builder', $VERSION );

__END__

=head1 NAME

Archive::Tar::Builder - Stream tarball data to a file handle

=head1 DESCRIPTION

Archive::Tar::Builder is meant to quickly and easily generate tarball streams,
and write them to a given file handle.  Though its options are few, its flexible
interface provides for a number of possible uses in many scenarios.

Archive::Tar::Builder supports path inclusions and exclusions, arbitrary file
name length, and the ability to add items from the filesystem into the archive
under an arbitrary name.

=head1 CONSTRUCTOR

=over

=item C<Archive::Tar::Builder-E<gt>new(%opts)>

Create a new Archive::Tar::Builder object.  The following options are honored:

=over

=item C<quiet>

When set, warnings encountered when reading individual files are not reported.

=item C<ignore_errors>

When set, non-fatal errors raised while archiving individual files do not
cause Archive::Tar::Builder to die() at the end of the stream.

=back

=back

=head1 ADDING MEMBERS TO ARCHIVE

=over

=item C<$archive-E<gt>add_as(%members)>

Add any number of members to the current archive, where the keys specified in
C<%members> specify the paths where the files exist on the filesystem, and the
values shall represent the eventual names of the members as they shall be
written upon archive writing.

=item C<$archive->E<gt>add(@paths)>

Add any number of members to the current archive.

=back

=head1 FILE PATH MATCHING

File path matching facilities exist to control, based on filenames and patterns,
which data should be included into and excluded from an archive made up of a
broad selection of files.

Note that file pattern matching operations triggered by usage of inclusions and
exclusions are performed against the names of the members of the archive as they
are added to the archive, not as the names of the files as they live in the
filesystem.

=head2 FILE PATH INCLUSIONS

File inclusions can be used to specify patterns which name members that should
be included into an archive, to the exclusion of other members.  File inclusions
take lower precedence to L<exclusions|FILE PATH EXCLUSIONS>.

=over

=item C<$archive-E<gt>include($pattern)>

Add a file match pattern, whose format is specified by fnmatch(3), for which
matching member names should be included into the archive.  Will die() upon
error.

=item C<$archive-E<gt>include_from_file($file)>

Import a list of file inclusion patterns from a flat file consisting of newline-
separated patterns.  Will die() upon error, especially failure to open a file
for reading inclusion patterns.

=back

=head2 FILE PATH EXCLUSIONS

=over

=item C<$archive-E<gt>exclude($pattern)>

Add a pattern which specifies that an exclusion of files and directories with
matching names should be excluded from the archive.  Note that exclusions take
higher priority than inclusions.  Will die() upon error.

=item C<$archive-E<gt>exclude_from_file($file)>

Add a number of patterns from a flat file consisting of exclusion patterns
separated by newlines.  Will die() upon error, especially when unable to open a
file for reading.

=back

=head2 TESTING EXCLUSIONS

=over

=item C<$archive-E<gt>is_excluded($path)>

Based on the file exclusion and inclusion patterns (respectively), determine if
the given path is to be excluded from the archive upon writing.

=back

=cut

sub is_excluded {
    my ( $self, $path ) = @_;

    return $self->{'match'}->is_excluded($path);
}

=head1 WRITING ARCHIVE DATA

=over

=item C<$archive-E<gt>write($handle)>

Write a tar stream of ustar format, with GNU tar extensions for supporting long
filenames and other POSIX extensions for files >8GB.  Files will be included
or excluded based on any possible previous usage of the filename inclusion and
exclusion calls.  Members will be written with the names given to them when they
were added to the archive, whether C<$archive-E<gt>add()> or
C<$archive-E<gt>add_as()> was used.

Returns the total number of bytes written.

=item C<$archive-E<gt>start($handle)>

A synonym for C<$archive-E<gt>write($handle)>.

=back

=head1 COPYRIGHT

Copyright (c) 2012, cPanel, Inc.
All rights reserved.
http://cpanel.net/

This is free software; you can redistribute it and/or modify it under the same
terms as Perl itself.  See L<perlartistic> for further details.
