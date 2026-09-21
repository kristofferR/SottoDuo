#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/prctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <time.h>
#include <unistd.h>

/* Kernel event age uses monotonic time; IPC uses the wall clock shared with Bun.
 * Bun's process.hrtime epoch is process-local, not Linux CLOCK_MONOTONIC. */
static int64_t event_timestamp(const struct input_event *event) {
  struct timespec monotonic, wall;
  if (clock_gettime(CLOCK_MONOTONIC, &monotonic) || clock_gettime(CLOCK_REALTIME, &wall)) return -1;
  int64_t age = (monotonic.tv_sec - event->time.tv_sec) * 1000000LL + monotonic.tv_nsec / 1000 - event->time.tv_usec;
  if (age < 0 || age > 250000) return -1;
  return (wall.tv_sec * 1000000LL + wall.tv_nsec / 1000 - age) / 1000;
}

/* Only the observed receiver Consumer Control interface. Never open or grab a general keyboard. */
int main(int argc, char **argv) {
  if (argc != 3) return 2;
  pid_t parent = getppid();
  if (parent <= 1 || prctl(PR_SET_PDEATHSIG, SIGKILL) || getppid() != parent) return 2;
  int fd = open(argv[1], O_RDONLY | O_NONBLOCK | O_CLOEXEC | O_NOFOLLOW);
  if (fd < 0) return 3;
  struct stat st;
  struct input_id id;
  char name[256] = {0}, sysfs[128], actual[PATH_MAX], expected[PATH_MAX];
  if (fstat(fd, &st) || !S_ISCHR(st.st_mode) || ioctl(fd, EVIOCGID, &id) < 0 ||
      id.bustype != BUS_USB || id.vendor != 0x2ca3 || id.product != 0x4011 ||
      ioctl(fd, EVIOCGNAME(sizeof(name)), name) < 0 ||
      strcmp(name, "DJI Technology Co., Ltd. Wireless Mic Rx Consumer Control")) return 4;
  snprintf(sysfs, sizeof(sysfs), "/sys/dev/char/%u:%u/device", major(st.st_rdev), minor(st.st_rdev));
  if (!realpath(sysfs, actual) || !realpath(argv[2], expected) ||
      strncmp(actual, expected, strlen(expected)) || actual[strlen(expected)] != '/') return 4;
  int clock_id = CLOCK_MONOTONIC;
  if (ioctl(fd, EVIOCSCLOCKID, &clock_id) < 0) return 4;
  struct input_event events[32];
  while (read(fd, events, sizeof(events)) > 0) {}
  if (errno != EAGAIN || ioctl(fd, EVIOCGRAB, 1) < 0) return 5;
  while (read(fd, events, sizeof(events)) > 0) {}
  if (errno != EAGAIN) return 5;
  puts("ready"); fflush(stdout);
  uint64_t sequence = 0;
  struct pollfd waits[2] = {{.fd = fd, .events = POLLIN}, {.fd = STDIN_FILENO, .events = POLLIN}};
  while (poll(waits, 2, -1) >= 0) {
    if (waits[1].revents || (waits[0].revents & (POLLERR | POLLHUP | POLLNVAL))) break;
    if (!(waits[0].revents & POLLIN)) continue;
    ssize_t bytes = read(fd, events, sizeof(events));
    if (bytes < 0 && errno == EAGAIN) continue;
    if (bytes <= 0 || bytes % sizeof(struct input_event)) break;
    for (size_t i = 0; i < (size_t)bytes / sizeof(struct input_event); i++) {
      struct input_event *event = &events[i];
      if (event->type == EV_SYN && event->code == SYN_DROPPED) goto done;
      if (event->type != EV_KEY || event->code != KEY_VOLUMEUP || event->value != 1) continue;
      int64_t timestamp = event_timestamp(event);
      if (timestamp < 0) continue;
      printf("press %llu %lld\n", (unsigned long long)++sequence, (long long)timestamp); fflush(stdout);
    }
  }
done:
  ioctl(fd, EVIOCGRAB, 0);
  close(fd);
  return 0;
}
