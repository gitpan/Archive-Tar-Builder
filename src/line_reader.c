/*-
 * Copyright (c) 2008 Tim Kientzle
 * Copyright (c) 2010 Joerg Sonnenberger
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer
 *    in this position and unchanged.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR(S) ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR(S) BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/*
 * Copyright (c) 2012, cPanel, Inc.
 * All rights reserved.
 * http://cpanel.net/
 *
 * This is free software; you can redistribute it and/or modify it under the
 * same terms as Perl itself.  See the Perl manual section 'perlartistic' for
 * further information.
 *
 * Modified for use in Archive::Tar::Builder.
 */

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "line_reader.h"

#if defined(_WIN32) && !defined(__CYGWIN__) && !defined(__BORLANDC__)
#define strdup _strdup
#endif

/*
 * Read lines from file and do something with each one.  If option_null
 * is set, lines are terminated with zero bytes; otherwise, they're
 * terminated with newlines.
 *
 * This uses a self-sizing buffer to handle arbitrarily-long lines.
 */
struct lafe_line_reader {
    FILE * f;
    char * buff;
    char * buff_end;
    char * line_start;
    char * line_end;
    char * p;
    char * pathname;
    size_t buff_length;
    int    nullSeparator; /* Lines separated by null, not CR/CRLF/etc. */
    int    ret;
};

struct lafe_line_reader *
lafe_line_reader(const char *pathname, int nullSeparator)
{
    struct lafe_line_reader *lr;

    if ((lr = calloc(1, sizeof(*lr))) == NULL) {
        errno = ENOMEM;

        return NULL;
    }

    lr->nullSeparator = nullSeparator;
    lr->pathname      = strdup(pathname);

    if (strcmp(pathname, "-") == 0) {
        lr->f = stdin;
    }
    else {
        lr->f = fopen(pathname, "r");
    }

    if (lr->f == NULL) {
        return NULL;
    }

    lr->buff_length = 8192;
    lr->line_start = lr->line_end = lr->buff_end = lr->buff = NULL;

    return lr;
}

static void
lafe_line_reader_find_eol(struct lafe_line_reader *lr)
{

    lr->line_end += strcspn(lr->line_end, lr->nullSeparator ? "" : "\x0d\x0a");
    *lr->line_end = '\0'; /* Noop if line_end == buff_end */
}

int
lafe_line_reader_next(struct lafe_line_reader *lr, const char **next)
{
    size_t bytes_wanted, bytes_read, new_buff_size;
    char *line_start, *p;

    for (;;) {
        /* If there's a line in the buffer, return it immediately. */
        while (lr->line_end < lr->buff_end) {
            line_start     = lr->line_start;
            lr->line_start = ++lr->line_end;

            lafe_line_reader_find_eol(lr);

            if (lr->nullSeparator || line_start[0] != '\0') {
                *next = line_start;

                return 0;
            }
        }

        /* If we're at end-of-file, process the final data. */
        if (lr->f == NULL) {
            if (lr->line_start == lr->buff_end) {
                /* No more text */
                *next = NULL;

                return 0;
            }

            line_start     = lr->line_start;
            lr->line_start = lr->buff_end;

            *next = line_start;

            return 0;
        }

        /* Buffer only has part of a line. */
        if (lr->line_start > lr->buff) {
            /* Move a leftover fractional line to the beginning. */
            memmove(lr->buff, lr->line_start,
                lr->buff_end - lr->line_start
            );

            lr->buff_end  -= lr->line_start - lr->buff;
            lr->line_end  -= lr->line_start - lr->buff;
            lr->line_start = lr->buff;
        }
        else {
            /* Line is too big; enlarge the buffer. */
            new_buff_size = lr->buff_length * 2;

            if (new_buff_size <= lr->buff_length) {
                errno = ENOMEM;
                *next = NULL;

                return -1;
            }

            lr->buff_length = new_buff_size;

            /*
             * Allocate one extra byte to allow terminating
             * the buffer.
             */
            if ((p = realloc(lr->buff, new_buff_size + 1)) == NULL) {
                errno = ENOMEM;
                *next = NULL;

                return -1;
            }

            lr->buff_end   = p + (lr->buff_end - lr->buff);
            lr->line_end   = p + (lr->line_end - lr->buff);
            lr->line_start = lr->buff = p;
        }

        /* Get some more data into the buffer. */
        bytes_wanted  = lr->buff + lr->buff_length - lr->buff_end;
        bytes_read    = fread(lr->buff_end, 1, bytes_wanted, lr->f);
        lr->buff_end += bytes_read;
        *lr->buff_end = '\0'; /* Always terminate buffer */

        lafe_line_reader_find_eol(lr);

        if (ferror(lr->f)) {
            *next = NULL;

            return -1;
        }

        if (feof(lr->f)) {
            if (lr->f != stdin) {
                fclose(lr->f);
            }

            lr->f = NULL;
        }
    }
}

void
lafe_line_reader_free(struct lafe_line_reader *lr)
{
    free(lr->buff);
    free(lr->pathname);
    free(lr);
}
