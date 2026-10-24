#include <mpv/client.h>
mpv_handle *screenshotTestCreateHandle(void);
void screenshotTestSetStatus(mpv_handle *handle, int status);
uint64_t screenshotTestLastID(mpv_handle *handle);
unsigned int screenshotTestSubmissions(mpv_handle *handle);
mpv_event *screenshotTestCreateReply(uint64_t request, int error, const char *filename);
void screenshotTestDestroyReply(mpv_event *event);
