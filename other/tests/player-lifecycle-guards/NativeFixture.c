#include "NativeBridge.h"
#include <stdlib.h>
#include <string.h>

struct mpv_handle { int unused; };
static struct mpv_handle handle;
static unsigned int calls, writes;
static int read_error, write_error, filter_shape, written_filter_count;
static mpv_node filter_values[2], filter_maps[2][1];
static char *filter_keys[] = { "name" };
static mpv_node_list filter_list, map_lists[2];

static void record(mpv_handle *value) { if (!value) abort(); calls++; }
mpv_handle *nativeTestHandle(void) { return &handle; }
void nativeTestReset(void) {
  calls = writes = 0; read_error = write_error = filter_shape = 0; written_filter_count = -1;
}
unsigned int nativeTestCalls(void) { return calls; }
unsigned int nativeTestWrites(void) { return writes; }
int nativeTestWrittenFilterCount(void) { return written_filter_count; }
void nativeTestSetReadError(int error) { read_error = error; }
void nativeTestSetWriteError(int error) { write_error = error; }
void nativeTestSetFilterShape(int shape) { filter_shape = shape; }

int mpv_get_property(mpv_handle *value, const char *name, mpv_format format, void *data) {
  record(value);
  if (read_error) return read_error;
  if (format == MPV_FORMAT_INT64) *(int64_t *)data = 7;
  else if (format == MPV_FORMAT_DOUBLE) *(double *)data = 1.5;
  else if (format == MPV_FORMAT_FLAG) *(int *)data = 1;
  else if (format == MPV_FORMAT_NODE) {
    mpv_node *node = data;
    if (strcmp(name, "vf") && strcmp(name, "af")) {
      *node = (mpv_node){ .format = MPV_FORMAT_DOUBLE, .u.double_ = 1.5 };
      return 0;
    }
    *node = (mpv_node){ .format = MPV_FORMAT_NODE_ARRAY, .u.list = &filter_list };
    filter_list = (mpv_node_list){ .num = 0, .values = filter_values };
    if (filter_shape == 1 || filter_shape == 4) {
      filter_list.num = 2;
      for (int index = 0; index < 2; index++) {
        filter_maps[index][0] = (mpv_node){ .format = MPV_FORMAT_STRING, .u.string = "crop" };
        if (filter_shape == 4) filter_maps[index][0] = (mpv_node){ .format = MPV_FORMAT_INT64, .u.int64 = 4 };
        map_lists[index] = (mpv_node_list){ .num = 1, .keys = filter_keys, .values = filter_maps[index] };
        filter_values[index] = (mpv_node){ .format = MPV_FORMAT_NODE_MAP, .u.list = &map_lists[index] };
      }
    } else if (filter_shape == 2) node->format = MPV_FORMAT_STRING, node->u.string = "unexpected";
    else if (filter_shape == 3) node->u.list = NULL;
  }
  return 0;
}
char *mpv_get_property_string(mpv_handle *value, const char *name) {
  (void)name; record(value); return read_error ? NULL : strdup("fixture");
}
int mpv_set_property(mpv_handle *value, const char *name, mpv_format format, void *data) {
  (void)name; record(value); writes++;
  if (format == MPV_FORMAT_NODE) {
    mpv_node *node = data;
    if (node->format == MPV_FORMAT_NODE_ARRAY) written_filter_count = node->u.list->num;
  }
  return write_error;
}
int mpv_set_property_string(mpv_handle *value, const char *name, const char *data) {
  (void)name; (void)data; record(value); writes++; return write_error;
}
int mpv_set_option(mpv_handle *value, const char *name, mpv_format format, void *data) {
  (void)name; (void)format; (void)data; record(value); return write_error;
}
int mpv_set_option_string(mpv_handle *value, const char *name, const char *data) {
  (void)name; (void)data; record(value); return write_error;
}
int mpv_observe_property(mpv_handle *value, uint64_t id, const char *name, mpv_format format) {
  (void)id; (void)name; (void)format; record(value); return 0;
}
int mpv_hook_add(mpv_handle *value, uint64_t id, const char *name, int priority) {
  (void)id; (void)name; (void)priority; record(value); return 0;
}
void mpv_free(void *data) { free(data); }
void mpv_free_node_contents(mpv_node *node) { (void)node; }
