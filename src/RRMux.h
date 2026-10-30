#ifndef RRMUX_H
#define RRMUX_H

/* Joins the video and audio tracks of two fragmented (CMAF / DASH) MP4 files into one ordinary MP4 with a normal sample table,
   which is what iOS 6's movie player understands. audioPath may be NULL for a silent clip.
   Returns 0 on success, otherwise a negative code (see RRMux.c) and a message in err. */
int rr_mux(const char *videoPath, const char *audioPath, const char *outPath, char *err, int errLen);

#endif
