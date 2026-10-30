/* Command line front end for src/RRMux.c: joins the video and audio tracks of two fragmented MP4 files into one MP4.
   Build: cc -Isrc -o mux_cli tools/mux_cli.c src/RRMux.c
   Usage: mux_cli video.mp4 [audio.mp4] out.mp4 */
#include <stdio.h>
#include "../src/RRMux.h"

int main(int argc, char **argv) {
    char err[200];
    if (argc < 3 || argc > 4) { fprintf(stderr, "usage: %s video.mp4 [audio.mp4] out.mp4\n", argv[0]); return 2; }
    int r = rr_mux(argv[1], argc > 3 ? argv[2] : NULL, argv[argc - 1], err, sizeof err);
    printf("rc=%d %s\n", r, err);
    return r != 0;
}
