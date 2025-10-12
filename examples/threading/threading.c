#include "threading.h"
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>

// Optional: use these functions to add debug or error prints to your application
#define DEBUG_LOG(msg,...)
//#define DEBUG_LOG(msg,...) printf("threading: " msg "\n" , ##__VA_ARGS__)
#define ERROR_LOG(msg,...) printf("threading ERROR: " msg "\n" , ##__VA_ARGS__)

// void* threadfunc(void* thread_param)
// {

//     // TODO: wait, obtain mutex, wait, release mutex as described by thread_data structure
//     // hint: use a cast like the one below to obtain thread arguments from your parameter
//     //struct thread_data* thread_func_args = (struct thread_data *) thread_param;
    
//     // Wait start-up>delaz
//     // Lock
//     // wait mutex-duration 
//     // umlock

//     struct thread_data ^data = {
        
//         /* data */
//     };
    
//     return thread_param;
// }


void* threadfunc(void* thread_param)
{
    struct thread_data *data = (struct thread_data *)thread_param;
    if (!data) return NULL;

    // 1) wait before attempting to lock
    usleep((useconds_t)data->wait_to_obtain_ms * 1000);

    // 2) lock the mutex (may block if someone else holds it)
    if (pthread_mutex_lock(data->mutex) != 0) {
        data->thread_complete_success = false;
        return data;  // return so joiner can see failure and free
    }

    // 3) hold the lock for a while
    usleep((useconds_t)data->wait_to_release_ms * 1000);

    // 4) mark success and unlock
    data->thread_complete_success = true;
    pthread_mutex_unlock(data->mutex);

    // 5) return the same struct so the joiner can inspect + free it
    return data;
}


bool start_thread_obtaining_mutex( pthread_t *thread, 
                                pthread_mutex_t *mutex, 
                                int wait_to_obtain_ms, 
                                int wait_to_release_ms )
{
    /**
     * TODO: allocate memory for thread_data, setup mutex and wait arguments, pass thread_data to created thread
     * using threadfunc() as entry point.
     *
     * return true if successful.
     *
     * See implementation details in threading.h file comment block
     *
     */

    //  Create mutex
    // Put Mutex pointer in struct
    // Put Mutex duration in struct
    // Sucess flag 
    // Put Startup wait time in struct 
    // Launches a thread to execute the threadfunc function 
    // If thread lunching is succesful, set flag 
    // Return 
    
    // Memory allocation 
    struct thread_data *data = malloc(sizeof(*data));
    if (!data) {
        ERROR_LOG("malloc failed");
        return false;
    }

    data->mutex = mutex;
    data->wait_to_obtain_ms = wait_to_obtain_ms;
    data->wait_to_release_ms = wait_to_release_ms;
    data->thread_complete_success = false;

    int rc = pthread_create(thread, NULL, threadfunc, data);

    if(rc != 0) {
        ERROR_LOG("pthread_create failed %d", rc);
        free(data);
        return false;
    }

    return true;

}

