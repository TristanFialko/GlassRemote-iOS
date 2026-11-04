/*
 * Glass Remote persistent TCP input server (Android, loopback only).
 *
 * Listens on 127.0.0.1:<port> and copies everything a client sends to stdout, which is piped
 * into a TV-side helper (UHID mouse / keyboard / cursor). Because this process owns the pipe,
 * a client disconnecting never closes the helper's stdin, so the virtual input device survives.
 *
 *   --port N       loopback port (1024..65535)
 *   --heartbeat    write "R\n" to stdout once per second while idle (cursor helper)
 *
 * Only ONE client is served at a time. A NEW connection REPLACES the current one: after iOS
 * suspends the app, its old ADB stream can linger half-dead, and the fresh connection must not
 * wait behind it.
 */
#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <unistd.h>

static int write_all(int fd, const void *buf, size_t len) {
    const unsigned char *p = buf;
    while (len) {
        ssize_t n = write(fd, p, len);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return -1;
        p += n;
        len -= (size_t)n;
    }
    return 0;
}

int main(int argc, char **argv) {
    int port = 0, heartbeat = 0;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--port") && i + 1 < argc) {
            port = atoi(argv[++i]);
        } else if (!strcmp(argv[i], "--heartbeat")) {
            heartbeat = 1;
        } else {
            fprintf(stderr, "ERROR unknown argument %s\n", argv[i]);
            return 2;
        }
    }
    if (port < 1024 || port > 65535) {
        fprintf(stderr, "ERROR invalid port\n");
        return 2;
    }

    signal(SIGPIPE, SIG_IGN);

    int listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) {
        fprintf(stderr, "ERROR socket: %s\n", strerror(errno));
        return 1;
    }

    int one = 1;
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((uint16_t)port);
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(listener, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        fprintf(stderr, "ERROR bind: %s\n", strerror(errno));
        close(listener);
        return 1;
    }
    if (listen(listener, 4) < 0) {
        fprintf(stderr, "ERROR listen: %s\n", strerror(errno));
        close(listener);
        return 1;
    }

    fprintf(stderr, "TCP_LISTENING 127.0.0.1:%d\n", port);
    fflush(stderr);

    int client = -1;
    unsigned char buf[2048];

    for (;;) {
        struct pollfd fds[2];
        nfds_t count = 0;

        fds[count].fd = listener;
        fds[count].events = POLLIN;
        fds[count].revents = 0;
        count++;

        if (client >= 0) {
            fds[count].fd = client;
            fds[count].events = POLLIN;
            fds[count].revents = 0;
            count++;
        }

        int ready = poll(fds, count, heartbeat ? 1000 : -1);
        if (ready < 0) {
            if (errno == EINTR) continue;
            fprintf(stderr, "ERROR poll: %s\n", strerror(errno));
            break;
        }
        if (ready == 0) {
            if (heartbeat && write_all(STDOUT_FILENO, "R\n", 2) < 0) break;
            continue;
        }

        /* Existing client first: its data (or its hang-up) is handled before any replacement. */
        if (client >= 0 && count == 2 && (fds[1].revents & (POLLIN | POLLHUP | POLLERR))) {
            ssize_t n = read(client, buf, sizeof(buf));
            if (n < 0 && errno == EINTR) {
                /* retry on the next loop */
            } else if (n <= 0) {
                close(client);
                client = -1;
            } else if (write_all(STDOUT_FILENO, buf, (size_t)n) < 0) {
                break; /* the helper is gone; exit so the phone restarts it */
            }
        }

        if (fds[0].revents & POLLIN) {
            int fresh = accept(listener, NULL, NULL);
            if (fresh >= 0) {
                if (client >= 0) close(client); /* newest connection wins */
                client = fresh;
            } else if (errno != EINTR) {
                fprintf(stderr, "ERROR accept: %s\n", strerror(errno));
            }
        }
    }

    if (client >= 0) close(client);
    close(listener);
    return 1;
}
