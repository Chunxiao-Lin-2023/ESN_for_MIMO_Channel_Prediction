#ifndef TCP_FILE_H
#define TCP_FILE_H

#ifdef __cplusplus
extern "C" {
#endif

#include "lwip/udp.h"
#include "lwip/pbuf.h"
#include "esn_core.h"
#include "xil_printf.h"
#include "udp_send.h"
#include "rls_training.h"
#include <string.h> // for memcpy, memset
#include <time.h>
#include <stdio.h>
#include "xtime_l.h"
#include "xparameters.h"

/* Buffer size for File Reception Buffer */
#define MAX_FILE_SIZE   (3072 * 3072)  /* 9MB (can be adjusted) */
#define MAX_BUFFER_SIZE (1024 * 1024)  /* 1MB (can be adjusted) */

/* The file header format:
 *  8 bytes for ID
 * +4 bytes for file_size
 * +4 bytes reserved
 * = 16 bytes total
 */
#define HEADER_SIZE 16

/* Sample Count: */
#define SAMPLES     140

/*UDP SENDING ENABLE FLAGS*/
#define SEND_DATA_OUT 1
#define SEND_PER_CHUNK_NMSE 1
#define SEND_OVERALL_NMSE 0

/*APPROXIMATION FLAG (for using fx functions in esn_core*/
#define FIXED_APPROX 0

/*PRINTING FLAGS*/
#define PRINT_OVERALL_NMSE 0
#define PRINT_PER_CHUNK_NMSE 1

/* Expected integer counts for each file: */
#define WIN_MAX     	(NUM_NEURONS * NUM_INPUTS)
#define WX_MAX      	(NUM_NEURONS * NUM_NEURONS)
#define WOUT_MAX    	(NUM_OUTPUTS * (NUM_INPUTS + NUM_NEURONS))
#define DATA_OUT_MAX    (NUM_OUTPUTS * SAMPLES)

/* Define a struct to match file header (packed) */
typedef struct __attribute__((__packed__)) {
    char file_id[8];
    uint32_t file_size;
    char reserved[4];
} file_header_t;

#ifndef UDP_CHUNK_BYTES
#define UDP_CHUNK_BYTES 1400  // safe vs. MTU=1500
#endif



/* Init function to allow udp_pcb for data transmission */
void start_tx_udp_init(void);

/* Init function to reset global state */
void udp_file_init(void);

/* Helper function for FP value printing (6 decimal places) */
void print_fixed_6(float val);

/* Print up to 'max_to_print' elements from a float array */
void print_float_array(const float *arr, int total_count, int max_to_print);

int parse_floats_into_array(const char *raw_text,
                                   unsigned int text_len,
                                   float *dest_array,
                                   unsigned int max_count);


/*
 * udp_recv_file:
 *   The main callback function handling file data arrival.
 *   - arg, pcb, p, addr, and port are lwIP parameters for the UDP callback.
 *   - p must be freed after use (to free buffer)
 */
void udp_recv_file(void *arg,
        struct udp_pcb *pcb,
        struct pbuf *p,
        const ip_addr_t *addr,
        u16_t port);


/*
 * udp_recv_file:
 *   The main callback function handling file data transmission (sending via chunks).
 *   - arg, pcb, p, addr, and port are lwIP parameters for the UDP callback.
 *   - p must be freed after use (to free buffer)
 */

void udp_send_cb(void *arg,
        struct udp_pcb *pcb,
        struct pbuf *p,
        const ip_addr_t *addr,
        u16_t port);

/* ESN-Related Function Prototypes */
void run_esn_calculation(int num_samples_in_chunk);
void reset_arrays(void);
void reset_data_in(void);

#ifdef __cplusplus
}
#endif

#endif /* UDP_FILE_H */
