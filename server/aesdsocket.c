#define _POSIX_C_SOURCE 200809L

#ifndef NI_MAXHOST
#define NI_MAXHOST 1025
#endif

#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <syslog.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <signal.h>
#include <pthread.h>
#include <time.h>
#include <sys/queue.h>

#define LISTEN_PORT "9000"
#define DATAFILE    "/var/tmp/aesdsocketdata"
#define BACKLOG     10
#define RECV_CHUNK  1024

static volatile sig_atomic_t g_exit_requested = 0;
static pthread_mutex_t       g_file_mutex = PTHREAD_MUTEX_INITIALIZER;

struct conn_data {
    int                     client_fd;
    struct sockaddr_storage peer;
    socklen_t               peerlen;
    bool                    thread_complete;
    pthread_t               tid;
    SLIST_ENTRY(conn_data)  entries;
};
SLIST_HEAD(conn_list, conn_data);

static void handle_signal(int signo) { (void)signo; g_exit_requested = 1; }

static int install_signal_handlers(void) {
    struct sigaction ign = {0};
    ign.sa_handler = SIG_IGN;
    if (sigaction(SIGPIPE, &ign, NULL) == -1) return -1;
    struct sigaction sa = {0};
    sa.sa_handler = handle_signal;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    if (sigaction(SIGINT,  &sa, NULL) == -1) return -1;
    if (sigaction(SIGTERM, &sa, NULL) == -1) return -1;
    return 0;
}

static int make_listen_socket(void) {
    struct addrinfo hints = {0}, *res = NULL, *rp = NULL;
    int sfd = -1, yes = 1;
    hints.ai_family   = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags    = AI_PASSIVE;
    int rc = getaddrinfo(NULL, LISTEN_PORT, &hints, &res);
    if (rc != 0) { syslog(LOG_ERR, "getaddrinfo: %s", gai_strerror(rc)); return -1; }
    for (rp = res; rp; rp = rp->ai_next) {
        sfd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (sfd == -1) continue;
        setsockopt(sfd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof yes);
        if (bind(sfd, rp->ai_addr, rp->ai_addrlen) == -1) { close(sfd); sfd=-1; continue; }
        if (listen(sfd, BACKLOG) == -1) { close(sfd); sfd=-1; continue; }
        syslog(LOG_INFO, "Listening on port %s", LISTEN_PORT);
        break;
    }
    freeaddrinfo(res);
    return sfd;
}

static int daemonize_after_bind(void) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid > 0) _exit(0);
    if (setsid() == -1) return -1;
    pid = fork();
    if (pid < 0) return -1;
    if (pid > 0) _exit(0);
    umask(0);
    if (chdir("/") == -1) return -1;
    close(STDIN_FILENO); close(STDOUT_FILENO); close(STDERR_FILENO);
    int fd = open("/dev/null", O_RDWR);
    if (fd >= 0) { dup2(fd,0); dup2(fd,1); dup2(fd,2); if (fd>2) close(fd); }
    return 0;
}

static int append_packet_and_reply(const char *packet, size_t pkt_len, int client_fd) {
    pthread_mutex_lock(&g_file_mutex);
    int df = open(DATAFILE, O_CREAT | O_WRONLY | O_APPEND, 0644);
    if (df == -1) { syslog(LOG_ERR, "open datafile: %s", strerror(errno)); pthread_mutex_unlock(&g_file_mutex); return -1; }
    ssize_t w = write(df, packet, pkt_len);
    close(df);
    if (w < 0 || (size_t)w != pkt_len) { syslog(LOG_ERR, "write datafile"); pthread_mutex_unlock(&g_file_mutex); return -1; }
    df = open(DATAFILE, O_RDONLY);
    if (df == -1) { pthread_mutex_unlock(&g_file_mutex); return -1; }
    char buf[RECV_CHUNK];
    for (;;) {
        ssize_t r = read(df, buf, sizeof buf);
        if (r == 0) break;
        if (r < 0) { if (errno == EINTR) continue; break; }
        size_t sent = 0;
        while (sent < (size_t)r) {
            ssize_t s = send(client_fd, buf + sent, (size_t)r - sent, 0);
            if (s < 0) { if (errno == EINTR) continue; goto done; }
            sent += (size_t)s;
        }
    }
done:
    close(df);
    pthread_mutex_unlock(&g_file_mutex);
    return 0;
}

static void *connection_thread(void *arg) {
    struct conn_data *cd = (struct conn_data *)arg;
    char host[NI_MAXHOST];
    if (getnameinfo((struct sockaddr *)&cd->peer, cd->peerlen,
                    host, sizeof host, NULL, 0, NI_NUMERICHOST) == 0)
        syslog(LOG_INFO, "Accepted connection from %s", host);
    char *accum = NULL;
    size_t cap = 0, len = 0;
    char buf[RECV_CHUNK];
    while (!g_exit_requested) {
        ssize_t r = recv(cd->client_fd, buf, sizeof buf, 0);
        if (r == 0) break;
        if (r < 0) { if (errno == EINTR) continue; break; }
        if (len + (size_t)r + 1 > cap) {
            size_t newcap = cap ? cap * 2 : 2048;
            while (newcap < len + (size_t)r + 1) newcap *= 2;
            char *tmp = realloc(accum, newcap);
            if (!tmp) { free(accum); accum = NULL; cap = len = 0; continue; }
            accum = tmp; cap = newcap;
        }
        memcpy(accum + len, buf, (size_t)r);
        len += (size_t)r;
        accum[len] = '\0';
        char *nlpos;
        while ((nlpos = memchr(accum, '\n', len)) != NULL) {
            size_t pkt_len = (size_t)(nlpos - accum) + 1;
            append_packet_and_reply(accum, pkt_len, cd->client_fd);
            size_t remaining = len - pkt_len;
            if (remaining) memmove(accum, accum + pkt_len, remaining);
            len = remaining;
        }
    }
    free(accum);
    syslog(LOG_INFO, "Closed connection from %s", host);
    close(cd->client_fd);
    cd->thread_complete = true;
    return cd;
}

static void *timestamp_thread(void *arg) {
    (void)arg;
    while (!g_exit_requested) {
        sleep(10);
        if (g_exit_requested) break;
        time_t t = time(NULL);
        struct tm *tm_info = localtime(&t);
        char timebuf[128];
        strftime(timebuf, sizeof timebuf, "timestamp:%a, %d %b %Y %T %z\n", tm_info);
        pthread_mutex_lock(&g_file_mutex);
        int df = open(DATAFILE, O_CREAT | O_WRONLY | O_APPEND, 0644);
        if (df != -1) {
            ssize_t wr = write(df, timebuf, strlen(timebuf));
            (void)wr;
            close(df);
        }
        pthread_mutex_unlock(&g_file_mutex);
    }
    return NULL;
}

int main(int argc, char *argv[]) {
    bool run_daemon = false;
    if (argc == 2 && strcmp(argv[1], "-d") == 0) run_daemon = true;
    else if (argc > 1) { fprintf(stderr, "Usage: %s [-d]\n", argv[0]); return EXIT_FAILURE; }

    openlog("aesdsocket", LOG_PID, LOG_USER);
    if (install_signal_handlers() == -1) { syslog(LOG_ERR, "sigaction"); closelog(); return -1; }

    int server_fd = make_listen_socket();
    if (server_fd == -1) { syslog(LOG_ERR, "Failed to set up listening socket"); closelog(); return -1; }

    if (run_daemon && daemonize_after_bind() == -1) {
        syslog(LOG_ERR, "daemonize failed"); close(server_fd); closelog(); return -1;
    }

    pthread_t ts_tid;
    pthread_create(&ts_tid, NULL, timestamp_thread, NULL);

    struct conn_list head;
    SLIST_INIT(&head);

    while (!g_exit_requested) {
        struct conn_data *cd, *nxt;
        for (cd = SLIST_FIRST(&head); cd != NULL; cd = nxt) {
            nxt = SLIST_NEXT(cd, entries);
            if (cd->thread_complete) {
                pthread_join(cd->tid, NULL);
                SLIST_REMOVE(&head, cd, conn_data, entries);
                free(cd);
            }
        }

        struct sockaddr_storage peer;
        socklen_t peerlen = sizeof(peer);
        int client_fd = accept(server_fd, (struct sockaddr *)&peer, &peerlen);
        if (client_fd == -1) {
            if (errno == EINTR && g_exit_requested) break;
            if (errno == EINTR) continue;
            syslog(LOG_ERR, "accept: %s", strerror(errno));
            continue;
        }

        struct conn_data *new_cd = malloc(sizeof *new_cd);
        if (!new_cd) { close(client_fd); continue; }
        new_cd->client_fd       = client_fd;
        new_cd->peer            = peer;
        new_cd->peerlen         = peerlen;
        new_cd->thread_complete = false;

        if (pthread_create(&new_cd->tid, NULL, connection_thread, new_cd) != 0) {
            syslog(LOG_ERR, "pthread_create: %s", strerror(errno));
            close(client_fd); free(new_cd); continue;
        }
        SLIST_INSERT_HEAD(&head, new_cd, entries);
    }

    struct conn_data *cd, *nxt;
    for (cd = SLIST_FIRST(&head); cd != NULL; cd = nxt) {
        nxt = SLIST_NEXT(cd, entries);
        pthread_join(cd->tid, NULL);
        SLIST_REMOVE(&head, cd, conn_data, entries);
        free(cd);
    }

    pthread_join(ts_tid, NULL);
    pthread_mutex_destroy(&g_file_mutex);
    syslog(LOG_INFO, "Caught signal, exiting");
    close(server_fd);
    if (unlink(DATAFILE) == -1 && errno != ENOENT)
        syslog(LOG_ERR, "unlink %s: %s", DATAFILE, strerror(errno));
    closelog();
    return 0;
}
