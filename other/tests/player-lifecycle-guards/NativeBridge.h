#include <mpv/client.h>
mpv_handle *nativeTestHandle(void);
void nativeTestReset(void);
unsigned int nativeTestCalls(void);
unsigned int nativeTestWrites(void);
int nativeTestWrittenFilterCount(void);
void nativeTestSetReadError(int error);
void nativeTestSetWriteError(int error);
void nativeTestSetFilterShape(int shape);
mpv_event *nativeTestCreateHook(uint64_t userdata, uint64_t id);
void nativeTestDestroyHook(mpv_event *event);
