#!/bin/sh

### BEGIN INIT INFO
# Provides:          aesdsocket
# Required-Start:    $remote_fs $syslog $network
# Required-Stop:     $remote_fs $syslog $network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start/stop aesdsocket daemon
### END INIT INFO


DAEMON="/usr/bin/aesdsocket"
NAME="aesdsocket"
PIDFILE="/var/run/${name}.pid"
DATAFILE="/var/tmp/aesdsocketdata"
DAEMON_OPTS="-d"
SSD="/sbin/start-stop-daemon"


# ensure runtime dirs exist
mkdir -p /var/run /var/tmp


start() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "$NAME is already running"
        return 0
    fi
    echo "Starting $NAME..."
    $SSD --start --quiet --make-pidfile --pidfile "$PIDFILE" --exec "$DAEMON" -- $DAEMON_OPTS
    RET=$?
    if [ $RET -eq 0 ]; then
        echo "$NAME started"
    else
        echo "Failed to start $NAME (rc=$RET)"
    fi
    return $RET
}

stop() {
    echo "Stopping $NAME..."
    if [ -f "$PIDFILE" ]; then
        $SSD --stop --quiet --pidfile "$PIDFILE" --signal TERM
        RET=$?
        # Wait briefly for cleanup done by the daemon
        sleep 1
        # Fall back: if daemon didn’t clean up data file, do it here
        # if [ -f "$DATAFILE" ]; then
        #     rm -f "$DATAFILE"
        # fi

        [ -f "$DATAFILE" ] && rm -f "$DATAFILE"
        rm -f "$PIDFILE"
        return $RET
    else
        # try by name if no pidfile (best effort)
        $SSD --stop --quiet --exec "$DAEMON" --signal TERM || true
        [ -f "$DATAFILE" ] && rm -f "$DATAFILE"
    fi
    echo "$NAME stopped"
}

status() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "$NAME is running as pid $(cat "$PIDFILE")"
        return 0
    fi
    echo "$NAME is not running"
    return 3
}

case "$1" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; start ;;
  status)  status ;;
  *) echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac

exit 0