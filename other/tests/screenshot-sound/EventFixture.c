#include "Bridge.h"
#include <stdlib.h>
#include <string.h>

struct mpv_handle { int status; uint64_t last_id; unsigned int submissions; };
mpv_handle *screenshotTestCreateHandle(void) { return calloc(1, sizeof(mpv_handle)); }
void screenshotTestSetStatus(mpv_handle *handle, int status) { handle->status = status; }
uint64_t screenshotTestLastID(mpv_handle *handle) { return handle->last_id; }
unsigned int screenshotTestSubmissions(mpv_handle *handle) { return handle->submissions; }
int mpv_command_async(mpv_handle *handle, uint64_t request, const char **arguments) {
  if (!arguments || !arguments[0] || strcmp(arguments[0], "screenshot") != 0) abort();
  handle->last_id = request; handle->submissions++;
  return handle->status;
}
mpv_event *screenshotTestCreateReply(uint64_t request, int error, const char *filename) {
  mpv_event *event = calloc(1, sizeof(*event));
  *event = (mpv_event){ .event_id = MPV_EVENT_COMMAND_REPLY, .reply_userdata = request, .error = error };
  if (filename) {
    mpv_event_command *command = calloc(1, sizeof(*command));
    mpv_node_list *map = calloc(1, sizeof(*map));
    *map = (mpv_node_list){ .num = 1, .keys = calloc(1, sizeof(char *)), .values = calloc(1, sizeof(mpv_node)) };
    map->keys[0] = strdup("filename");
    map->values[0] = (mpv_node){ .format = MPV_FORMAT_STRING, .u.string = strdup(filename) };
    command->result = (mpv_node){ .format = MPV_FORMAT_NODE_MAP, .u.list = map };
    event->data = command;
  }
  return event;
}
void screenshotTestDestroyReply(mpv_event *event) {
  if (event->data) {
    mpv_event_command *command = event->data;
    mpv_node_list *map = command->result.u.list;
    free(map->keys[0]); free(map->keys); free(map->values[0].u.string); free(map->values); free(map); free(command);
  }
  free(event);
}
