#include <mpv/client.h>
mpv_handle *nativeTestHandle(void);
void nativeTestReset(void);
unsigned int nativeTestCalls(void);
unsigned int nativeTestWrites(void);
int nativeTestWrittenFilterCount(void);
void nativeTestSetReadError(int error);
void nativeTestSetWriteError(int error);
void nativeTestSetFilterShape(int shape);
