/*
 * Copyright (c) 2012, cPanel, Inc.
 * All rights reserved.
 * http://cpanel.net/
 *
 * This is free software; you can redistribute it and/or modify it under the
 * same terms as Perl itself.  See the Perl manual section 'perlartistic' for
 * further information.
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <sys/types.h>
#include <errno.h>
#include "b_string.h"
#include "b_find.h"
#include "b_error.h"
#include "b_builder.h"

typedef b_builder * Archive__Tar__Builder;

struct builder_options {
    int    quiet;
    int    ignore_errors;
    int    follow_symlinks;
    size_t block_factor;
};

static int builder_lookup(SV *cache, uid_t uid, gid_t gid, b_string **user, b_string **group) {
    dSP;
    I32 retc;

    ENTER;
    SAVETMPS;

    /*
     * Prepare the stack for $cache->getpwuid()
     */
    PUSHMARK(SP);
    XPUSHs(cache);
    XPUSHs(sv_2mortal(newSViv(uid)));
    XPUSHs(sv_2mortal(newSViv(gid)));
    PUTBACK;

    if ((retc = call_method("lookup", G_ARRAY)) < 2) {
        goto error_lookup;
    }

    SPAGAIN;

    if (retc == 2) {
        size_t len = 0;
        SV *item;
        char *tmp;

        if ((item = POPs) != NULL && SvOK(item)) {
            tmp = SvPV(item, len);

            if ((*group = b_string_new_len(tmp, len)) == NULL) {
                goto error_string_new_group;
            }
        }

        if ((item = POPs) != NULL && SvOK(item)) {
            tmp = SvPV(item, len);

            if ((*user = b_string_new_len(tmp, len)) == NULL) {
                goto error_string_new_user;
            }
        }
    }

    PUTBACK;

    FREETMPS;
    LEAVE;

    return 0;

error_string_new_user:
    b_string_free(*group);

error_string_new_group:

error_lookup:
    PUTBACK;

    FREETMPS;
    LEAVE;

    return -1;
}

static void builder_warn(b_error *err) {
    if (err == NULL) return;

    warn("%s: %s: %s", b_error_path(err)->str, b_error_message(err)->str, strerror(b_error_errno(err)));
}

static int find_flags(struct builder_options *options) {
    int flags = 0;

    if (options == NULL) return 0;

    if (options->follow_symlinks) flags |= B_FIND_FOLLOW_SYMLINKS;

    return flags;
}

MODULE = Archive::Tar::Builder PACKAGE = Archive::Tar::Builder PREFIX = builder_

Archive::Tar::Builder
builder_new(klass, ...)
    char *klass

    CODE:
        b_builder *builder;
        b_error *err;
        SV *cache = NULL;
        I32 i, retc;
        struct builder_options *options;

        if ((items - 1) % 2 != 0) {
            croak("Uneven number of arguments passed; must be in 'key' => 'value' format");
        }

        if ((options = malloc(sizeof(*options))) == NULL) {
            croak("%s: %s", "malloc()", strerror(errno));
        }

        options->quiet           = 0;
        options->ignore_errors   = 0;
        options->block_factor    = 0;
        options->follow_symlinks = 0;

        for (i=1; i<items; i+=2) {
            char *key = SvPV_nolen(ST(i));
            SV *value = ST(i+1);

            if (strcmp(key, "quiet")           == 0 && SvIV(value)) options->quiet           = 1;
            if (strcmp(key, "ignore_errors")   == 0 && SvIV(value)) options->ignore_errors   = 1;
            if (strcmp(key, "block_factor")    == 0 && SvIV(value)) options->block_factor    = SvIV(value);
            if (strcmp(key, "follow_symlinks") == 0 && SvIV(value)) options->follow_symlinks = 1;
        }

        if ((builder = b_builder_new(options->block_factor)) == NULL) {
            croak("%s: %s", "b_builder_new()", strerror(errno));
        }

        err = b_builder_get_error(builder);

        if (!options->quiet) {
            b_error_set_callback(err, B_ERROR_CALLBACK(builder_warn));
        }

        /*
         * Call Archive::Tar::Builder::UserCache->new()
         */
        PUSHMARK(SP);
        XPUSHs(sv_2mortal(newSVpvf("Archive::Tar::Builder::UserCache")));
        PUTBACK;

        if ((retc = call_method("new", G_SCALAR)) >= 1) {
            cache = POPs;
            SvREFCNT_inc(cache);
        }

        PUTBACK;

        b_builder_set_lookup_service(builder, B_LOOKUP_SERVICE(builder_lookup), cache); 
        b_builder_set_data(builder, options);

        RETVAL = builder;

    OUTPUT:
        RETVAL

void
builder_DESTROY(builder)
    Archive::Tar::Builder builder

    CODE:
        b_builder_destroy(builder);

void
builder_include(builder, pattern)
    Archive::Tar::Builder builder
    const char *pattern

    CODE:
        if (b_builder_include(builder, pattern) < 0) {
            croak("Cananot add inclusion pattern '%s' to list of inclusions: %s", pattern, strerror(errno));
        }

void
builder_include_from_file(builder, file)
    Archive::Tar::Builder builder
    const char *file

    CODE:
        if (b_builder_include_from_file(builder, file) < 0) {
            croak("Cannot add items to inclusion list from file %s: %s", file, strerror(errno));
        }

void
builder_exclude(builder, pattern)
    Archive::Tar::Builder builder
    const char *pattern

    CODE:
        if (b_builder_exclude(builder, pattern) < 0) {
            croak("Cannot add exclusion pattern '%s' to list of exclusions: %s", pattern, strerror(errno));
        }

void
builder_exclude_from_file(builder, file)
    Archive::Tar::Builder builder
    const char *file

    CODE:
        if (b_builder_exclude_from_file(builder, file) < 0) {
            croak("Cannot add items to exclusion list from file %s: %s", file, strerror(errno));
        }

int
builder_is_excluded(builder, path)
    Archive::Tar::Builder builder
    const char *path

    CODE:
        RETVAL = b_builder_is_excluded(builder, path);

    OUTPUT:
        RETVAL

void
builder_set_handle(builder, fh)
    Archive::Tar::Builder builder
    PerlIO *fh

    CODE:
        b_buffer *buf = b_builder_get_buffer(builder);;

        b_buffer_set_fd(buf, PerlIO_fileno(fh));

size_t
builder_archive_as(builder, ...)
    Archive::Tar::Builder builder

    CODE:
        struct builder_options *options = builder->data;
        b_buffer *buf = b_builder_get_buffer(builder);

        size_t i;

        if ((items - 1) % 2 != 0) {
            croak("Uneven number of arguments passed; must be in 'path' => 'member_name' format");
        }

        if (b_buffer_get_fd(buf) == 0) {
            croak("No file handle set");
        }

        for (i=1; i<items; i+=2) {
            int flags = find_flags(options);

            b_string *path        = b_string_new(SvPV_nolen(ST(i)));
            b_string *member_name = b_string_new(SvPV_nolen(ST(i+1)));

            if (b_find(builder, path, member_name, B_FIND_CALLBACK(b_builder_write_file), flags) < 0) {
                croak("%s: %s: %s\n", "b_find()", path->str, strerror(errno));
            }
        }

        RETVAL = builder->total;

    OUTPUT:
        RETVAL

size_t
builder_archive(builder, ...)
    Archive::Tar::Builder builder

    CODE:
        struct builder_options *options = builder->data;
        b_buffer *buf = b_builder_get_buffer(builder);

        size_t i;

        if (items <= 1) {
            croak("No paths to archive specified");
        }

        if (b_buffer_get_fd(buf) == 0) {
            croak("No file handle set");
        }

        for (i=1; i<items; i++) {
            int flags = find_flags(options);

            b_string *path = b_string_new(SvPV_nolen(ST(i)));

            if (b_find(builder, path, path, B_FIND_CALLBACK(b_builder_write_file), flags) < 0) {
                croak("%s: %s: %s\n", "b_find()", path->str, strerror(errno));
            }

            b_string_free(path);
        }

        RETVAL = builder->total;

    OUTPUT:
        RETVAL

ssize_t
builder_flush(builder)
    Archive::Tar::Builder builder

    CODE:
        ssize_t ret;

        b_buffer *buf = b_builder_get_buffer(builder);

        if (b_buffer_get_fd(buf) == 0) {
            croak("No file handle set");
        }

        if ((ret = b_buffer_flush(buf)) < 0) {
            croak("%s: %s", "b_buffer_flush()", strerror(errno));
        }

        RETVAL = ret;

    OUTPUT:
        RETVAL

ssize_t
builder_finish(builder)
    Archive::Tar::Builder builder

    CODE:
        ssize_t ret;

        b_buffer *buf = b_builder_get_buffer(builder);
        b_error *err  = b_builder_get_error(builder);

        struct builder_options *options = builder->data;

        if (b_buffer_get_fd(buf) == 0) {
            croak("No file handle set");
        }

        if ((ret = b_buffer_flush(buf)) < 0) {
            croak("%s: %s", "b_buffer_flush()", strerror(errno));
        }

        if (b_error_warn(err) && !options->ignore_errors) {
            croak("Delayed nonzero exit status");
        }

        b_error_reset(err);

        RETVAL = ret;

    OUTPUT:
        RETVAL
