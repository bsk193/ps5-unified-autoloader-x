#ifndef VERSION_X_H
#define VERSION_X_H

/* AUTOLOADER_X_VERSION: our own semver ("1.0.0", "1.0.1-beta.1"), set from the
 * x-v* git tag by the Makefile (-DAUTOLOADER_X_VERSION=...).
 * AUTOLOADER_X_VERSION_UPSTREAM: the upstream itsPLK release this fork is based on.
 *
 * AUTOLOADER_VERSION in include/autoloader.h stays upstream's and is never
 * edited, so merging upstream never conflicts on the version line. */
#include "autoloader.h"

#ifndef AUTOLOADER_X_VERSION
#define AUTOLOADER_X_VERSION "0.0.0-dev"
#endif

#define AUTOLOADER_X_VERSION_UPSTREAM AUTOLOADER_VERSION

#endif
