// Bounded direct child used only inside the lifecycle sandbox; no subprocesses.
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
int main(int argc, char **argv) {
  if (argc != 4) return 64;
  if (!strcmp(argv[3], "ignore-term")) signal(SIGTERM, SIG_IGN);
  FILE *pid = fopen(argv[2], "w");
  if (!pid) return 65;
  fprintf(pid, "%d", getpid()); fclose(pid);
  setbuf(stdout, NULL); setbuf(stderr, NULL);
  puts("stdout-ready"); fputs("stderr-ready\n", stderr);
  for (int i = 0; i < 1200; i++) {
    if (access(argv[1], F_OK) == 0) { puts("stdout-done"); return 0; }
    usleep(50000);
  }
  return 70;
}
