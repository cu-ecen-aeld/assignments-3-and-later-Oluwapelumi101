#define _POSIX_C_SOURCE 200809L

#ifndef NI_MAXHOST
#define NI_MAXHOST 1025
#endif

// Standard Library Headers
#include <stdio.h>      // printf, perror, FILE, etc.
#include <stdlib.h>     // malloc, free, exit, etc.
#include <stdbool.h>    //bool, true, false
#include <stdarg.h>     //handing variable arguements
#include <string.h>     // string functions 
#include <errno.h>      //errno and codes

/****************************************************
 * System and File I/O Headers
 ****************************************************/
#include <unistd.h>      //close, read, write, fork, getpid
#include <fcntl.h>       //open 
#include <sys/types.h>   //system data types
#include <sys/stat.h>    //file status
#include <sys/file.h>    //flock
#include <syslog.h>      // syslog, openlog, closelog

/****************************************************
 * Networking Headers
 ****************************************************/
#include <sys/socket.h>     //sockets, bind, listen, accept
#include <netdb.h>          //getaddrinfo, freeaddrinfo
#include <arpa/inet.h>  // inet_ntop, inet_pton, htons, ntohs
#include <netinet/in.h> // sockaddr_in, IPPROTO_TCP, etc.

/****************************************************
 * Signals and Process Control
 ****************************************************/
#include <signal.h>     // signal handling (sigaction, sigemptyset)

/****************************************************
 * Project-Specific Macros and Constants
 ****************************************************/
#define LISTEN_PORT "9000"
#define DATAFILE "/var/tmp/aesdsocketdata"
#define BACKLOG 10
#define RECV_CHUNK 1024

static volatile sig_atomic_t g_exit_requested = 0;


// Catching Sigint/Sigterm

static void handle_signal(int signo) {
    (void)signo;
    g_exit_requested = 1;
}

static int install_signal_handlers(void) {
    // Ignore SIGPIPE so writing to a closed socket doesn't terminate the process.
    struct sigaction ign = {0};
    ign.sa_handler = SIG_IGN;
    if (sigaction(SIGPIPE, &ign, NULL) == -1)
        return -1;

    // Set up INT/TERM to request graceful shutdown.
    struct sigaction sa = {0};
    sa.sa_handler = handle_signal;
    sigemptyset(&sa.sa_mask);
    // sa.sa_flags = SA_RESTART;  
    sa.sa_flags = 0;              

    if (sigaction(SIGINT,  &sa, NULL) == -1)
        return -1;

    if (sigaction(SIGTERM, &sa, NULL) == -1)
        return -1;

    return 0;
}

// Create, bind and listen 
static int make_listen_socket(void) {
    struct addrinfo hints = {0}, *res = NULL, *rp = NULL;
    int sfd = -1;
    int yes = 1;

    // Fill in the hints
    hints.ai_family = AF_UNSPEC;
    hints.ai_family   = AF_UNSPEC;     // IPv4 or IPv6
    hints.ai_socktype = SOCK_STREAM;   // TCP
    hints.ai_flags    = AI_PASSIVE;    // for bind()
    
    // Resolve local addresses
    int rc = getaddrinfo(NULL, LISTEN_PORT, &hints, &res);
    if (rc != 0) {
        syslog(LOG_ERR, "getaddrinfo: %s", gai_strerror(rc));
        return -1;
    }
    
    // Try each address until one works
    for (rp = res; rp != NULL; rp = rp->ai_next) {
        // Create the socket
        sfd = socket(rp->ai_family, rp->ai_socktype, rp->ai_protocol);
        if (sfd == -1) continue;

        if (setsockopt(sfd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes)) == -1) {
            close(sfd);
            sfd = -1;
            continue;
        }

        #ifdef IPV6_V6ONLY
                if (rp->ai_family == AF_INET6) {
                    // Accept both v6 and v4-mapped if possible
                    int no = 0;
                    setsockopt(sfd, IPPROTO_IPV6, IPV6_V6ONLY, &no, sizeof(no));
                }
        #endif

        if (bind(sfd, rp->ai_addr, rp->ai_addrlen) == -1) {
            close(sfd);
            sfd = -1;
            continue;
        }

        if (listen(sfd, BACKLOG) == -1) {
            close(sfd);
            sfd = -1;
            continue;
        }

        syslog(LOG_INFO, "Listening on port %s", LISTEN_PORT);
        break; // success
    }

    freeaddrinfo(res);
    return sfd; // -1 on failure
}

// Running in the background
static int daemonize_after_bind(void) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid > 0) _exit(0); // parent exits

    if (setsid() == -1) return -1;
    pid = fork();
    if (pid < 0) return -1;
    if (pid > 0) _exit(0);

    umask(0);
    if (chdir("/") == -1) return -1;

    // Close std fds
    close(STDIN_FILENO);
    close(STDOUT_FILENO);
    close(STDERR_FILENO);

    int fd = open("/dev/null", O_RDWR);
    if (fd >= 0) {
        dup2(fd, STDIN_FILENO);
        dup2(fd, STDOUT_FILENO);
        dup2(fd, STDERR_FILENO);
        if (fd > 2) close(fd);
    }
    return 0;
}

static int append_packet_and_reply(const char *packet, size_t pkt_len, int client_fd) {
    // Append packet to DATAFILE atomically-ish (with file lock)
    int df = open(DATAFILE, O_CREAT | O_WRONLY | O_APPEND, 0644);
    if (df == -1) {
        syslog(LOG_ERR, "open datafile: %s", strerror(errno));
        return -1;
    }

    // Use advisory lock to avoid races if you later add concurrency
    if (flock(df, LOCK_EX) == -1) {
        syslog(LOG_ERR, "flock: %s", strerror(errno));
        close(df);
        return -1;
    }

    ssize_t w = write(df, packet, pkt_len);
    if (w < 0 || (size_t)w != pkt_len) {
        syslog(LOG_ERR, "write datafile: %s", strerror(errno));
        flock(df, LOCK_UN);
        close(df);
        return -1;
    }

    // Rewind by closing and reopening for read to send full file
    flock(df, LOCK_UN);
    close(df);

    df = open(DATAFILE, O_RDONLY);
    if (df == -1) {
        syslog(LOG_ERR, "open datafile for read: %s", strerror(errno));
        return -1;
    }

    char buf[RECV_CHUNK];
    for (;;) {
        ssize_t r = read(df, buf, sizeof buf);
        if (r == 0) break;
        if (r < 0) {
            if (errno == EINTR) continue;
            syslog(LOG_ERR, "read datafile: %s", strerror(errno));
            close(df);
            return -1;
        }

        size_t sent = 0;
        while (sent < (size_t)r) {
            ssize_t s = send(client_fd, buf + sent, (size_t)r - sent, 0);
            if (s < 0) {
                if (errno == EINTR) continue;
                syslog(LOG_ERR, "send: %s", strerror(errno));
                close(df);
                return -1;
            }
            sent += (size_t)s;
        }
    }

    close(df);
    return 0;
}

int main(int argc, char *argv[]) {
    bool run_daemon = false;

    if (argc == 2 && strcmp(argv[1], "-d") == 0) {
        run_daemon = true;
    } else if (argc > 1) {
        fprintf(stderr, "Usage: %s [-d]\n", argv[0]);
        return EXIT_FAILURE;
    }

    openlog("aesdsocket", LOG_PID, LOG_USER);

    if (install_signal_handlers() == -1) {
        syslog(LOG_ERR, "sigaction: %s", strerror(errno));
        closelog();
        return -1;
    }

    int server_fd = make_listen_socket();
    if (server_fd == -1) {
        // “failing and returning -1 if any of the socket connection steps fail”
        syslog(LOG_ERR, "Failed to set up listening socket");
        closelog();
        return -1;
    }

    if (run_daemon) {
        if (daemonize_after_bind() == -1) {
            syslog(LOG_ERR, "daemonize failed: %s", strerror(errno));
            close(server_fd);
            closelog();
            return -1;
        }
    }

    // // Wait until socket is ready to accept connections (Valgrind-safe)
    // {
    //     int retries = 50; // up to ~5 seconds total
    //     while (retries--) {
    //         int test_fd = socket(AF_INET, SOCK_STREAM, 0);
    //         if (test_fd < 0) break; // shouldn't happen
    //         struct sockaddr_in sa = {0};
    //         sa.sin_family = AF_INET;
    //         sa.sin_port = htons(9000);
    //         sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    //         if (connect(test_fd, (struct sockaddr *)&sa, sizeof(sa)) == 0) {
    //             close(test_fd);
    //             break; // socket is ready
    //         }
    //         close(test_fd);
    //         usleep(100000); // 0.1s
    //     }
    // }
    
    // Main accept loop
    while (!g_exit_requested) {
        struct sockaddr_storage peer;
        socklen_t peerlen = sizeof peer;
        int client_fd = accept(server_fd, (struct sockaddr *)&peer, &peerlen);
        if (client_fd == -1) {
            if (errno == EINTR && g_exit_requested) break;
            if (errno == EINTR) continue;
            syslog(LOG_ERR, "accept: %s", strerror(errno));
            continue;
        }

        char host[NI_MAXHOST];
        if (getnameinfo((struct sockaddr *)&peer, peerlen,
                        host, sizeof host, NULL, 0, NI_NUMERICHOST) == 0) {
            syslog(LOG_INFO, "Accepted connection from %s", host);
        } else {
            syslog(LOG_INFO, "Accepted connection");
        }

        // Receive until we see a newline; handle partial chunks
        char *accum = NULL;
        size_t cap = 0, len = 0;
        char buf[RECV_CHUNK];

        // bool have_packet = false;
        while (!g_exit_requested) {
            ssize_t r = recv(client_fd, buf, sizeof buf, 0);
            if (r == 0) {
                // Peer closed; break out—if we didn't see newline, nothing to append
                break;
            }
            if (r < 0) {
                if (errno == EINTR) continue;
                syslog(LOG_ERR, "recv: %s", strerror(errno));
                break;
            }

            // Grow buffer
            if (len + (size_t)r + 1 > cap) {
                size_t newcap = (cap ? cap * 2 : 2048);
                while (newcap < len + (size_t)r + 1) newcap *= 2;
                char *tmp = realloc(accum, newcap);
                if (!tmp) {
                    syslog(LOG_ERR, "malloc failed, dropping over-length packet");
                    // Discard current in-flight packet
                    free(accum);
                    accum = NULL; cap = len = 0;
                    continue;
                }
                accum = tmp; cap = newcap;
            }

            memcpy(accum + len, buf, (size_t)r);
            len += (size_t)r;
            accum[len] = '\0';

            // Check for newline
            // char *nlpos = memchr(accum, '\n', len);
            // if (nlpos) {
            //     // have_packet = true;
            //     size_t pkt_len = (nlpos - accum) + 1; // include newline

            //     // Append packet and reply with full file content
            //     if (append_packet_and_reply(accum, pkt_len, client_fd) == -1) {
            //         // keep going but log already done
            //     }

            //     // Shift any bytes after newline into new packet accumulator
            //     size_t remaining = len - pkt_len;
            //     if (remaining) memmove(accum, accum + pkt_len, remaining);
            //     len = remaining;
            //     // We could loop to handle multiple packets in same recv burst.
            //     // Continue; if more '\n' present, the next loop will pick them up.
            //     // have_packet = false; // we handled that one
            // }
            // Process *all* complete packets present
            while (1) {
                char *nlpos = memchr(accum, '\n', len);
                if (!nlpos) break;
                size_t pkt_len = (size_t)(nlpos - accum) + 1; // include newline
                append_packet_and_reply(accum, pkt_len, client_fd);
                size_t remaining = len - pkt_len;
                if (remaining) memmove(accum, accum + pkt_len, remaining);
                len = remaining;
            }

            
        } 



        // Close connection
        if (getnameinfo((struct sockaddr *)&peer, peerlen,
                        host, sizeof host, NULL, 0, NI_NUMERICHOST) == 0) {
            syslog(LOG_INFO, "Closed connection from %s", host);
        } else {
            syslog(LOG_INFO, "Closed connection");
        }

        free(accum);
        close(client_fd);
    }

    syslog(LOG_INFO, "Caught signal, exiting");
    close(server_fd);
    // Best-effort delete data file
    if (unlink(DATAFILE) == -1 && errno != ENOENT) {
        syslog(LOG_ERR, "unlink %s: %s", DATAFILE, strerror(errno));
    }
    closelog();
    return 0;

}


