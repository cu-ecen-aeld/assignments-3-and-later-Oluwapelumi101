C Cheat Sheet

char c = 'A';     // just one byte a char 


char str[] = "Hello";    // array of chars

char *s = "Hello";       // pointer to the first char of string

char *arr[] = {"one", "two", "three"};   // array of pointers

char **p = arr;   // pointer to array of pointers


| What you have    | What function expects | How to pass   |
| ---------------- | --------------------- | ------------- |
| `int x;`         | `void f(int);`        | `f(x);`       |
| `int x;`         | `void f(int*);`       | `f(&x);`      |
| `int arr[10];`   | `void f(int*);`       | `f(arr);`     |
| `char str[];`    | `void f(char*);`      | `f(str);`     |
| `char *p;`       | `void f(char*);`      | `f(p);`       |
| `float vals[5];` | `void f(float*,int);` | `f(vals, 5);` |

1. Basics
char c = 'A';     // a single char
char *p = &c;     // pointer to char (stores address of c)

printf("%c\n", c);    // 'A'
printf("%p\n", (void*)&c); // address of c
printf("%p\n", (void*)p);  // same address
printf("%c\n", *p);   // 'A' (dereference pointer)

2. Arrays (string is just a char array)
char str[] = "Hi";   // array of 3 chars: 'H','i','\0'
char *p = str;       // str "decays" to pointer to first element

printf("%s\n", str); // "Hi"
printf("%s\n", p);   // "Hi"
printf("%c\n", str[0]); // 'H'
printf("%c\n", *p);     // 'H'


3. Integers

int x = 42;
int *p = &x;

printf("%d\n", x);   // 42
printf("%d\n", *p);  // 42 (dereference)
*p = 100;            // change x via pointer
printf("%d\n", x);   // 100



4. Arrays of numbers
int arr[3] = {1,2,3};
int *p = arr;          // arr decays to &arr[0]

printf("%d\n", arr[1]);   // 2
printf("%d\n", *(p+1));   // 2 (pointer arithmetic)


5. Pointer to pointer
int x = 10;
int *p = &x;
int **pp = &p;

printf("%d\n", **pp);  // 10


6. Functions
void print_char(char c) { printf("%c\n", c); }
void print_char_ptr(char *p) { printf("%c\n", *p); }

int main() {
    char c = 'Z';
    print_char(c);    // pass value
    print_char_ptr(&c); // pass pointer
}



7. Special with strings

void print_str(char *s) { printf("%s\n", s); }

int main() {
    char msg[] = "Hello";
    print_str(msg);   // array decays to pointer
}




8. &arr vs arr vs &arr[0]
int arr[3] = {10,20,30};
int *p1 = arr;       // pointer to first int
int *p2 = &arr[0];   // same
int (*p3)[3] = &arr; // pointer to entire array of 3 ints

printf("%d\n", p1[1]);   // 20
printf("%d\n", (*p3)[1]); // 20


// Syslog Guide 
Syslog intro
🛠 Key syslog functions (from <syslog.h>)
1. openlog()
openlog(const char *ident, int option, int facility);


Initializes connection to syslog.

ident: string prefix for your program (e.g. "writer").

option (bitmask):

LOG_PID → include process ID in logs.

LOG_CONS → write to console if logging fails.

LOG_NDELAY → open immediately, don’t wait for first message.

facility: category. Common ones:

LOG_USER (default for user apps)

LOG_DAEMON, LOG_LOCAL0–LOG_LOCAL7, LOG_MAIL, etc.

👉 Example:

openlog("writer", LOG_PID | LOG_CONS, LOG_USER);



2. syslog()
syslog(int priority, const char *format, ...);


Logs a message with a given priority (severity + facility).

Priorities (ordered by severity):

LOG_EMERG → system is unusable.

LOG_ALERT → action must be taken immediately.

LOG_CRIT → critical condition.

LOG_ERR → error condition.

LOG_WARNING → warning condition.

LOG_NOTICE → normal but significant.

LOG_INFO → informational.

LOG_DEBUG → debug-level messages.

👉 Example:

syslog(LOG_ERR, "Failed to open file: %s", strerror(errno));
syslog(LOG_DEBUG, "Writing %s to %s", writestr, writefile);


closelog();


#include <stdio.h>
#include <syslog.h>
#include <unistd.h>

int main(void) {
    // Connect to syslog
    openlog("syslog_demo", LOG_PID | LOG_CONS, LOG_USER);

    syslog(LOG_EMERG,   "EMERG: System is unusable!");
    syslog(LOG_ALERT,   "ALERT: Immediate action required!");
    syslog(LOG_CRIT,    "CRIT: Critical condition detected");
    syslog(LOG_ERR,     "ERR: An error occurred");
    syslog(LOG_WARNING, "WARNING: This is just a warning");
    syslog(LOG_NOTICE,  "NOTICE: Something noteworthy happened");
    syslog(LOG_INFO,    "INFO: Informational message");
    syslog(LOG_DEBUG,   "DEBUG: Debugging details here");

    closelog();
    return 0;
}

