#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <mpv/client.h>

enum {
  playbackTimeoutSeconds = 30
};

static int setOption(mpv_handle *mpv, const char *name, const char *value) {
  int result = mpv_set_option_string(mpv, name, value);
  if (result < 0) {
    fprintf(stderr, "Unable to set --%s=%s: %s\n", name, value, mpv_error_string(result));
  }
  return result;
}

static void printProperty(mpv_handle *mpv, const char *name) {
  char *value = mpv_get_property_string(mpv, name);
  printf("%s=%s\n", name, value == NULL ? "<unavailable>" : value);
  mpv_free(value);
}

static int verifyCodec(mpv_handle *mpv) {
  char *codec = mpv_get_property_string(mpv, "current-tracks/video/codec");
  if (codec == NULL) {
    fprintf(stderr, "The video codec property is unavailable\n");
    return EXIT_FAILURE;
  }

  int result = EXIT_SUCCESS;
  if (strcmp(codec, "vvc") != 0) {
    fprintf(stderr, "Expected the vvc codec, found %s\n", codec);
    result = EXIT_FAILURE;
  }

  printf("current-tracks/video/codec=%s\n", codec);
  mpv_free(codec);
  printProperty(mpv, "video-codec");
  printProperty(mpv, "hwdec-current");
  return result;
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "Usage: %s <VVC media file>\n", argv[0]);
    return EXIT_FAILURE;
  }

  mpv_handle *mpv = mpv_create();
  if (mpv == NULL) {
    fprintf(stderr, "Unable to create an mpv instance\n");
    return EXIT_FAILURE;
  }

  const char *options[][2] = {
    {"ao", "null"},
    {"audio", "no"},
    {"config", "no"},
    {"load-scripts", "no"},
    {"msg-level", "all=warn"},
    {"pause", "yes"},
    {"vo", "null"},
    {"ytdl", "no"}
  };
  for (size_t index = 0; index < sizeof(options) / sizeof(options[0]); ++index) {
    if (setOption(mpv, options[index][0], options[index][1]) < 0) {
      mpv_terminate_destroy(mpv);
      return EXIT_FAILURE;
    }
  }

  int result = mpv_initialize(mpv);
  if (result < 0) {
    fprintf(stderr, "Unable to initialize mpv: %s\n", mpv_error_string(result));
    mpv_terminate_destroy(mpv);
    return EXIT_FAILURE;
  }

  const char *command[] = {"loadfile", argv[1], NULL};
  result = mpv_command(mpv, command);
  if (result < 0) {
    fprintf(stderr, "Unable to load %s: %s\n", argv[1], mpv_error_string(result));
    mpv_terminate_destroy(mpv);
    return EXIT_FAILURE;
  }

  int64_t deadline = mpv_get_time_ns(mpv) +
    playbackTimeoutSeconds * INT64_C(1000000000);
  while (mpv_get_time_ns(mpv) < deadline) {
    mpv_event *event = mpv_wait_event(mpv, 1.0);
    switch (event->event_id) {
    case MPV_EVENT_PLAYBACK_RESTART:
      result = verifyCodec(mpv);
      mpv_terminate_destroy(mpv);
      return result;
    case MPV_EVENT_END_FILE: {
      mpv_event_end_file *endFile = event->data;
      if (endFile != NULL && endFile->reason == MPV_END_FILE_REASON_ERROR) {
        fprintf(stderr, "Playback failed: %s\n", mpv_error_string(endFile->error));
      } else {
        fprintf(stderr, "Playback ended before the first frame was decoded\n");
      }
      mpv_terminate_destroy(mpv);
      return EXIT_FAILURE;
    }
    case MPV_EVENT_QUEUE_OVERFLOW:
      fprintf(stderr, "The mpv event queue overflowed\n");
      mpv_terminate_destroy(mpv);
      return EXIT_FAILURE;
    case MPV_EVENT_SHUTDOWN:
      fprintf(stderr, "mpv shut down before the first frame was decoded\n");
      mpv_terminate_destroy(mpv);
      return EXIT_FAILURE;
    default:
      break;
    }
  }

  fprintf(stderr, "Timed out waiting for the first decoded frame\n");
  mpv_terminate_destroy(mpv);
  return EXIT_FAILURE;
}
