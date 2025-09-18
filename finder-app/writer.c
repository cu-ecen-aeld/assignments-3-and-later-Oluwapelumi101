// C program to write a string in a file

#include <stdio.h>
#include <stdlib.h>
#include <syslog.h>
#include <errno.h>
#include <string.h>


int main(int argc, char *argv[]) {
    // open the file to be written

    openlog("writer", LOG_PID | LOG_CONS, LOG_USER);

    // ah

    if (argc != 3) {
        syslog(LOG_ERR, "Invalid arguments. Usage: %s <writefile> <writestr>", argv[0]);
        closelog();
        return 1;
    }

    const char *writeFile = argv[1];
    const char *writeStr  = argv[2];


    // Log debug info 
    syslog(LOG_DEBUG, "Writing %s to %s", writeStr, writeFile);

    // Opening File with user buffer
    FILE *fp = fopen(writeFile, "w");
    if (fp == NULL ) {
        syslog(LOG_ERR, "Failed to open file %s, %s", writeFile, strerror(errno));
        closelog();
        return 1;
    }

    // Writing into file 
    if( fputs(writeStr, fp) == EOF) {
        syslog(LOG_ERR, "Failed to write to '%s': %s", writeFile, strerror(errno));
        fclose(fp);
        closelog();
        return 1;
    }
    if (fclose(fp) != 0) {
        syslog(LOG_ERR, "Failed to close file '%s': %s", writeFile, strerror(errno));
        closelog();
        return 1;
    }


    closelog();
    return 0;

}