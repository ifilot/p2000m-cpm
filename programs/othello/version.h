#ifndef P2000M_OTHELLO_VERSION_H
#define P2000M_OTHELLO_VERSION_H

/*
 * User-visible game version.  The compiler supplies __DATE__ separately so
 * development binaries can be identified without changing this semantic
 * version for every build.
 */
#define OTHELLO_VERSION "v1.0.0"
#define OTHELLO_BUILD_DATE __DATE__

#endif
