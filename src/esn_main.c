/*******************************************************************************
 * File: tcp_file.c
 * Author: Christopher Boerner
 * Date: 04-01-2025
 *
 * Description:
 *	   Store files sent over Ethernet in a 1MB buffer (from 3MB file buffer),
 *	   parse the file's floating-point values, and run the ESN core.
 *
 *   Expected Files:
 *     - DATAIN
 *     - WIN
 *     - WX
 *     - WOUT
 *     - GOLDEN SOLUTION
 *
 ******************************************************************************/
/*
 * Modifications by Ahmed Malik, Virginia Tech ECE, 2025.
 * - Changed tcp naming convention to UDP instead
 * - tcp_recv_file() changed to udp_recv_file()
 *   -Changed callback type
 */

#include "esn_main.h"

/* Global/Static variables local to this file */
static char file_buffer[MAX_FILE_SIZE];
static unsigned int file_offset = 0;
static unsigned int expected_file_size = 0;
static int expecting_header = 1;
//static int global_data_in_samples = 0;

/* Arrays for ESN Equations */
static float w_in[WIN_MAX];
static float w_x[WX_MAX];
static float w_out[WOUT_MAX];
static float golden_data_out[DATA_OUT_MAX];
static int golden_sample_count = 0;

static float *data_in = NULL;
static int data_in_count = 0;  // Total number of floats parsed

/* Flags to track readiness */
static int w_in_ready = 0;
static int w_x_ready = 0;
//static int w_out_ready = 0;
static int golden_data_out_ready = 0;

// Keep state_pre consistent between chunks
static float state_pre[NUM_NEURONS] = {0};

// Performance metrics to keep consistent
static float cumulative_mse     = 0.0f;
static int   cumulative_samples = 0;
static int total_samples_processed = 0;    // cumulative sample count

static XTime __ts_start, __ts_stop;
static u64   __last_latency_ns;

/* Output provider: ESN publish a buffer safely */
//static const float *g_out_buf = NULL;
//static uint32_t     g_out_count_floats = 0;   // number of floats
//static volatile int g_out_ready = 0;

static struct udp_pcb *pcb_tx = NULL;
static ip_addr_t g_pc_addr;
static u16_t g_pc_rx_port = UDP_TX_PORT;
static int g_pc_known = 0; // start unknown


/*Init function for udp chunk transfer from fpga -> pc*/
void start_tx_udp_init(void) {
    pcb_tx = udp_new();
    if (!pcb_tx) { xil_printf("TX: cannot alloc pcb\n\r"); return; }
    // ephemeral source port (recommended) OR a distinct fixed one like 6001
    err_t e = udp_bind(pcb_tx, IP_ADDR_ANY, 0);
    if (e != ERR_OK) { xil_printf("TX: bind failed %d\n\r"); return; }
    xil_printf("TX: ready (ephemeral source port)\n\r");
}


///* Init function to reset global state */
void udp_file_init(void)
{
    memset(file_buffer, 0, sizeof(file_buffer));
    file_offset = 0;
    expected_file_size = 0;
    expecting_header = 1;


}


/* Called by your ESN code when results are ready */
//void publish_output_buffer(const float *buf, uint32_t count_floats) {
//    g_out_buf = buf;
//    g_out_count_floats = count_floats;
//    g_out_ready = 1;
//}

/* Optional: clear when consumed */
//void clear_output_buffer(void) {
//    g_out_ready = 0;
//    g_out_buf = NULL;
//    g_out_count_floats = 0;
//}


static void print_scientific(float val)
{
    char buf[32];  // Buffer size for the formatted string.

    // Format the float in scientific notation (exponent form).
    sprintf(buf, "%e", val);
    xil_printf("%s", buf);
}

/* Helper function for FP value printing (6 decimal places) */
void print_fixed_6(float val)
{
    /* Handle sign */
    int negative = (val < 0.0f);
    if (negative) {
        val = -val;  /* positive for easier math */
    }

    /* Separate integer and fraction */
    int iPart = (int)val;
    float frac = val - (float)iPart;

    /* Multiply fraction by 1,000,000 to get 6 decimal places */
    int fPart = (int)((frac * 1000000.0f) + 0.5f); /* rounding */

    /* Print sign */
    if (negative) {
        xil_printf("-");
    }

    /* Print integer part, then dot, then zero‐padded fraction */
    xil_printf("%d.%06d", iPart, fPart);
}

/* Print up to 'max_to_print' elements from a float array */
void print_float_array(const float *arr, int total_count, int max_to_print)
{
    /* Decide how many elements to print: */
    int limit = (total_count < max_to_print) ? total_count : max_to_print;

    for (int i = 0; i < limit; i++) {
        xil_printf("arr[%d] = ", i);
        print_scientific(arr[i]);
        xil_printf("\n\r");
    }
    xil_printf("\n\r");
}

/* Helper function to read lines or space-delimited values from the buffer and convert to FP values */
int parse_floats_into_array(const char *raw_text,
                                   unsigned int text_len,
                                   float *dest_array,
                                   unsigned int max_count)
{
    // Using static buffer instead of malloc() for data_out (heap was overflowing)
    static char static_buf[MAX_BUFFER_SIZE];
    if (text_len >= sizeof(static_buf)) {
        xil_printf("Error: File too large for static buffer.\n\r");
        return 0;
    }

    memcpy(static_buf, raw_text, text_len);
    static_buf[text_len] = '\0';  // Null-terminate the buffer

    unsigned int count = 0;
    char *line = strtok(static_buf, "\n");
    while (line && count < max_count) {
        float val = 0.0f;
        if (sscanf(line, "%f", &val) == 1) {
            dest_array[count++] = val;
        }
        line = strtok(NULL, "\n");
    }
    return count;
}

/* ---- helper used to send header ---- */
static err_t send_header(struct udp_pcb *pcb, const ip_addr_t *addr, u16_t port,
                         const char file_id8[8], uint32_t payload_bytes)
{
    file_header_t hdr;
    memset(&hdr, 0, sizeof(hdr));
    memcpy(hdr.file_id, file_id8, 8);
    hdr.file_size = payload_bytes;  // keep consistent with your Python/C reader (endianness)

    struct pbuf *ph = pbuf_alloc(PBUF_TRANSPORT, sizeof(hdr), PBUF_RAM);
    if (!ph) return ERR_MEM;
    memcpy(ph->payload, &hdr, sizeof(hdr));
    err_t e = udp_sendto(pcb, ph, addr, port);
    pbuf_free(ph);
    return e;
}

/* ---- helper used to send data UDP_CHUNK_BYTES length at a time---- */
static err_t send_bytes_chunked(struct udp_pcb *pcb, const ip_addr_t *addr, u16_t port,
                                const uint8_t *buf, uint32_t len)
{
    uint32_t off = 0;
    while (off < len) {
        uint16_t n = (uint16_t)((len - off) > UDP_CHUNK_BYTES ? UDP_CHUNK_BYTES : (len - off));
        struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, n, PBUF_RAM);
        if (!p) return ERR_MEM;
        memcpy(p->payload, buf + off, n);
        err_t e = udp_sendto(pcb, p, addr, port);
        pbuf_free(p);
        if (e != ERR_OK) return e;
        off += n;
    }
    return ERR_OK;
}


/* If you want TEXT floats that match parse_floats_into_array() */
static uint32_t count_text_bytes(const float *arr, uint32_t cnt) {
    char tmp[64]; uint32_t total=0;
    for (uint32_t i=0;i<cnt;i++) {
        int n = snprintf(tmp, sizeof(tmp), "%e\n", arr[i]);
        if (n < 0) return 0;
        total += (uint32_t)n;
    }
    return total;
}

/* The actual UDP callback function (called in udp_perf_server.c) for receiving UDP file*/
void udp_recv_file(void *arg, struct udp_pcb *pcb,struct pbuf *p,const ip_addr_t *addr,u16_t port)
{
	// Defensive; UDP usually supplies p
    if (!p) return;
//    // start timestamp
//    XTime_GetTime(&__ts_start);
    // Learn the sender as “the PC” if not known
	if (!g_pc_known) {
		g_pc_addr = *addr;           // copy IP
		g_pc_known = 1;
		// g_pc_rx_port is the PC's port you are going to send TO
		/*xil_printf("Learned PC at %d.%d.%d.%d (dest port=%u)\n\r",
			ip4_addr1(&g_pc_addr), ip4_addr2(&g_pc_addr),
			ip4_addr3(&g_pc_addr), ip4_addr4(&g_pc_addr),
			g_pc_rx_port);*/
	}


    // Temp pointer 'q' to iterate through the pbuf chain
    struct pbuf *q = p;
    unsigned int bytes_copied = 0; // total number of bytes copied

    // Loop through all linked pbuf segments (in case packet is chained)
    while (q) {
    	// Length of current segment
        unsigned int copy_len = q->len;

        /* Avoid buffer overflow if file is too large */
        if (file_offset + copy_len > MAX_FILE_SIZE) {
            copy_len = MAX_FILE_SIZE - file_offset;
        }

        // Copy current segment's payload into file buffer at correct offset
        memcpy(&file_buffer[file_offset], q->payload, copy_len);

        // Update buffer with # of bytes copied
        file_offset += copy_len;

        // Accumulate total # of bytes copied
        bytes_copied += copy_len;

        // Next pbuf in chain
        q = q->next;
    }

    /* Free pbuf after copying */
    pbuf_free(p);

    /* Check if we've parsed the header yet */
    if (expecting_header && file_offset >= HEADER_SIZE) {
        file_header_t *hdr = (file_header_t*)file_buffer;
        expected_file_size = hdr->file_size;

        char file_id_str[9];
        memcpy(file_id_str, hdr->file_id, 8);
        file_id_str[8] = '\0';
//        xil_printf("Header -> ID: %s, Size: %u bytes\n\r",
//                   file_id_str, expected_file_size);

        expecting_header = 0;
    }

    /* Check if we've received the full file payload */
    if (!expecting_header &&
        file_offset >= (HEADER_SIZE + expected_file_size)) {

        /* Re-interpret the header to get the file ID */
        file_header_t *hdr = (file_header_t*)file_buffer;
        char file_id_str[9];
        memcpy(file_id_str, hdr->file_id, 8);
        file_id_str[8] = '\0';  // null-terminate

        /*
         * Now decide what to do based on file ID.
         */
        if (strncmp(hdr->file_id, "WIN_____", 8) == 0) {
            parse_floats_into_array(
                &file_buffer[HEADER_SIZE],
                expected_file_size,
                w_in,
                WIN_MAX
            );
            w_in_ready = 1;
        }
        else if (strncmp(hdr->file_id, "WX______", 8) == 0) {
            parse_floats_into_array(
                &file_buffer[HEADER_SIZE],
                expected_file_size,
                w_x,
                WX_MAX
            );
            w_x_ready = 1;
        }
        else if (strncmp(hdr->file_id, "WOUT____", 8) == 0) {
        	int parsedCount = parse_floats_into_array(
                &file_buffer[HEADER_SIZE],
                expected_file_size,
                w_out,
                WOUT_MAX
            );

            // Optionally check that the expected number of floats was parsed.
            if (parsedCount != WOUT_MAX) {
                xil_printf("Warning: Expected %d floats for W_out but parsed %d floats.\n\r", WOUT_MAX, parsedCount);
            }

            // Use the setter function to update the global W_out matrix.
            set_W_out(w_out);
        }
        else if (strncmp(hdr->file_id, "DATAIN__", 8) == 0) {
            // Allocate memory for data_in dynamically
            int max_possible_floats = expected_file_size / 8;
            if (data_in != NULL) {
                free(data_in);
            }
            data_in = (float *)malloc(sizeof(float) * max_possible_floats);
            //error checking to see how many bytes are being requested
//            xil_printf("malloc request: %u floats (%u bytes)\n\r", max_possible_floats,
//                       (unsigned)(max_possible_floats*sizeof(float)));

            if (data_in == NULL) {
                xil_printf("Error: Unable to allocate memory for data_in.\n\r");
                return ERR_MEM;
            }

            // Now parse the floats into data_in.
            int total_floats = parse_floats_into_array(
                &file_buffer[HEADER_SIZE],
                expected_file_size,
                data_in,
                max_possible_floats
            );
            data_in_count = total_floats;
            int num_samples = total_floats / NUM_INPUTS;
//            xil_printf("DATAIN file: parsed %d floats, which is %d sample(s)\n\r", total_floats, num_samples);

            /* RUN ESN */
            run_esn_calculation(num_samples);
        }
        else if (strncmp(hdr->file_id, "DATAOUT_", 8) == 0) {
        	// In your DATAOUT branch (in tcp_recv_file or a separate routine):
        	int total_floats = parse_floats_into_array(&file_buffer[HEADER_SIZE],
        	                                            expected_file_size,
        	                                            golden_data_out,
        	                                            DATA_OUT_MAX);
        	golden_sample_count = total_floats / NUM_OUTPUTS;
        	xil_printf("Golden DATAOUT file: parsed %d floats, which is %d sample(s)\n\r", total_floats, golden_sample_count);
            golden_data_out_ready = 1;
        }

        /* Reset for the next file */
        file_offset = 0;
        expected_file_size = 0;
        expecting_header = 1;
        memset(file_buffer, 0, sizeof(file_buffer));
    }

}



/* ESN core calling function with error checking */
void run_esn_calculation(int num_samples_in_chunk)
{
    /* Check if each required file/array is ready. If not, say so. */
    int missing = 0;
    if (!w_in_ready || !w_x_ready) {
        xil_printf("Cannot run ESN. The following are missing:\n\r");
        if (!w_in_ready) {
            xil_printf("  - w_in.dat (WIN_____)\n\r");
            missing++;
        }
        if (!w_x_ready) {
            xil_printf("  - w_x.dat (WX______)\n\r");
            missing++;
        }
        xil_printf("Total missing: %d file(s).\n\r", missing);
        return;
    }

//    // start timestamp
//    XTime_GetTime(&__ts_start);

    // Create ESN arrays (can be reset from chunk to chunk)
    float res_state[NUM_NEURONS];
    float state_extended[EXTENDED_STATE_SIZE];
    float data_out[NUM_OUTPUTS];
    float out_chunk[NUM_OUTPUTS * num_samples_in_chunk];

    // For overall error accumulation:
    float total_mse = 0.0f;
    int samples_compared = 0;

    for (int sample = 0; sample < num_samples_in_chunk; sample++) {

    	// Pointer to current sample in the new chunk data_in
        float *current_sample = &data_in[sample * NUM_INPUTS];

        // Use the current updated W_out:
        float *current_W_out = get_W_out();

        // Process current sample using the persistent state_pre
        if (FIXED_APPROX){
        	update_state_fx(w_in, current_sample, w_x, state_pre, res_state);
        }
        else{
        	update_state(w_in, current_sample, w_x, state_pre, res_state);
        }

        // Update state_pre for the next sample
        for (int i = 0; i < NUM_NEURONS; i++) {
            state_pre[i] = res_state[i];
        }

        form_state_extended(current_sample, res_state, state_extended);

        if(FIXED_APPROX){
        	compute_output_fx(current_W_out, state_extended, data_out);
        }
        else{
        	compute_output(current_W_out, state_extended, data_out);
        }
        memcpy(&out_chunk[sample * NUM_OUTPUTS], data_out, sizeof(float) * NUM_OUTPUTS);
//        // end timestamp
//        XTime_GetTime(&__ts_stop);
//        // compute difference in CPU ticks
//        u64 ticks = __ts_stop - __ts_start;
//        // convert ticks -> nanoseconds
//        // CPU clock freq in Hz is XPAR_CPU_CORTEXA9_0_CPU_CLK_FREQ_HZ
//        __last_latency_ns = ticks * 1000000000ULL / XPAR_CPU_CORTEXA9_0_CPU_CLK_FREQ_HZ;
//
//        xil_printf("  → end‐to‐end latency for %d sample(s): %llu ns\n\r",
//                   num_samples_in_chunk,
//                   (unsigned long long)__last_latency_ns);

        // Compare output with golden output for the current sample, if available
        if ((total_samples_processed + sample) < golden_sample_count) {

        	// Pointer to the corresponding golden output (128 floats per sample)
            float *golden_sample = &golden_data_out[(total_samples_processed + sample) * NUM_OUTPUTS];
            update_training_rls(state_extended, golden_sample);

            float mse;
            if(FIXED_APPROX){
            	mse = compute_mse_fx(data_out, golden_sample, NUM_OUTPUTS);
            }
            else{
            	mse = compute_mse(data_out, golden_sample, NUM_OUTPUTS);
            }

            total_mse += mse;
            samples_compared++;

            // Update the output weights using the online RLS training function.
//            update_training_rls(state_extended, golden_sample);
//            float *new_W_out = get_W_out();
//            xil_printf("Printing W_out_%d", (total_samples_processed + sample));
//            xil_printf("\n\r");
//            print_float_array(new_W_out, WOUT_MAX, 3);
        }
        else {
            xil_printf("No golden output available for sample %d.\n\r", sample);
        }
    }

    // batch results
//    if (samples_compared > 0) {
//        float avg_mse = total_mse / samples_compared;
//        xil_printf("Batch avg MSE over %d sample(s): ", samples_compared);
//        print_scientific(avg_mse);
//        xil_printf("\n\r");
//        float nmse_db = 10.0f * log10f(avg_mse);
//        xil_printf("Batch NMSE(dB): ");
//        print_scientific(nmse_db);
//        xil_printf("\n\r");
//    } else {
//        xil_printf("No samples compared in this chunk.\n\r");
//    }

    // update and print file‐wise (cumulative) results
    cumulative_mse     += total_mse;
    cumulative_samples += samples_compared;

    if (cumulative_samples > 0) {
        float file_avg_mse = cumulative_mse / cumulative_samples;

        float avg_nmse_db = 10.0f * log10f(total_mse/samples_compared);
        float overall_nmse_db = 10.0f * log10f(file_avg_mse);

        if(PRINT_PER_CHUNK_NMSE){
			xil_printf("Samples %d-%d\n\r", total_samples_processed,
						   total_samples_processed + num_samples_in_chunk);
			xil_printf("Average NMSE(dB): ");
			print_scientific(avg_nmse_db);
			xil_printf("\n\r");
		}
//        xil_printf("Overall avg MSE over %d sample(s): ", cumulative_samples);
//        print_scientific(file_avg_mse);
//        xil_printf("\n\r");


        if(PRINT_OVERALL_NMSE){
			xil_printf("Samples 0-%d\n\r",
						   total_samples_processed + num_samples_in_chunk);
			xil_printf("Overall NMSE(dB): ");
			print_scientific(overall_nmse_db);
			xil_printf("\n\r");
        }

        //Assumption: You are sending per_chunk or overall (not both at once, otherwise result will be in same file)
        if(SEND_PER_CHUNK_NMSE){
			char avg_nmse_line[64];
			int n = snprintf(avg_nmse_line, sizeof(avg_nmse_line), "%e\n", avg_nmse_db);
			if (n > 0 && n < (int)sizeof(avg_nmse_line)) {
				// 1) header
				err_t e = send_header(pcb_tx, &g_pc_addr, g_pc_rx_port, "NMSE_CHK", (uint32_t)n);
				if (e == ERR_OK) {
					// 2) payload
					struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, (u16_t)n, PBUF_RAM);
					if (p) {
						memcpy(p->payload, avg_nmse_line, (size_t)n);
						e = udp_sendto(pcb_tx, p, &g_pc_addr, g_pc_rx_port);
						pbuf_free(p);
						if (e != ERR_OK) xil_printf("TX: NMSE_CHK send err %d\n\r", e);
					}
				} else {
					xil_printf("TX: NMSE_CHK hdr err %d\n\r", e);
				}
			}
        }
        if(SEND_OVERALL_NMSE){
        	char overall_nmse_line[64];
        	int n = snprintf(overall_nmse_line, sizeof(overall_nmse_line), "%e\n", overall_nmse_db);
        	if (n > 0 && n < (int)sizeof(overall_nmse_line)) {
        	    // 1) header
        	    err_t e = send_header(pcb_tx, &g_pc_addr, g_pc_rx_port, "NMSE_CHK", (uint32_t)n);
        	    if (e == ERR_OK) {
        	        // 2) payload
        	        struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, (u16_t)n, PBUF_RAM);
        	        if (p) {
        	            memcpy(p->payload, overall_nmse_line, (size_t)n);
        	            e = udp_sendto(pcb_tx, p, &g_pc_addr, g_pc_rx_port);
        	            pbuf_free(p);
        	            if (e != ERR_OK) xil_printf("TX: NMSE_CHK send err %d\n\r", e);
        	        }
        	    } else {
        	        xil_printf("TX: NMSE_CHK hdr err %d\n\r", e);
        	    }
        	}

        }

    }

    total_samples_processed += num_samples_in_chunk;
//    xil_printf("Chunk processed. Total samples processed: %d\n\r",
//               total_samples_processed);

    if (SEND_DATA_OUT){
		/*--------------------UDP TRANSMIT----------------------*/
		//For sending output back to UDP for current chunk
		if (!pcb_tx) {
			xil_printf("TX: pcb not initialized\n\r");
			return;
		}
		if (!g_pc_known) {
			xil_printf("TX: PC not learned yet; skipping send\n\r");
			return;
		}
		uint32_t total_floats  = (uint32_t)num_samples_in_chunk * (uint32_t)NUM_OUTPUTS;
		uint32_t payload_bytes = count_text_bytes(out_chunk, total_floats);

		// 1) header
		err_t e = send_header(pcb_tx, &g_pc_addr, g_pc_rx_port, "DATAOUT_", payload_bytes);
		if (e != ERR_OK) { xil_printf("TX hdr err %d\n\r", e); return; }

		// 2) stream text lines into a rolling UDP chunk buffer
		char txbuf[UDP_CHUNK_BYTES];
		uint32_t pos = 0;

		for (uint32_t i = 0; i < total_floats; ++i) {
			int n = snprintf(txbuf + pos, sizeof(txbuf) - pos, "%e\n", out_chunk[i]);
			if (n < 0) { xil_printf("fmt err\n\r"); return; }

			if ((uint32_t)n >= (sizeof(txbuf) - pos) || pos >= sizeof(txbuf) - 64) {
				e = send_bytes_chunked(pcb_tx, &g_pc_addr, g_pc_rx_port,
									   (const uint8_t*)txbuf, pos);
				if (e != ERR_OK) { xil_printf("send err %d\n\r", e); return; }
				pos = 0;

				if ((uint32_t)n >= sizeof(txbuf)) { xil_printf("line too big\n\r"); return; }
				n = snprintf(txbuf + pos, sizeof(txbuf) - pos, "%e\n", out_chunk[i]);
				pos += (uint32_t)n;
			} else {
				pos += (uint32_t)n;
			}
		}

		// tail
		if (pos) {
			e = send_bytes_chunked(pcb_tx, &g_pc_addr, g_pc_rx_port,
								   (const uint8_t*)txbuf, pos);
			if (e != ERR_OK) { xil_printf("tail err %d\n\r", e); return; }
		}

		/*xil_printf("TX: chunk sent (%lu floats) → %d.%d.%d.%d:%u\n\r",
				   (unsigned long)total_floats,
				   ip4_addr1(&g_pc_addr), ip4_addr2(&g_pc_addr),
				   ip4_addr3(&g_pc_addr), ip4_addr4(&g_pc_addr),
				   g_pc_rx_port);*/

		// Send EOF ONLY if this was the last chunk of the session (140 total, etc.)

		if (total_samples_processed >= SAMPLES) {
			send_header(pcb_tx, &g_pc_addr, g_pc_rx_port, "EOF_____", 0);
		}
    }

}

/* Soft reset function */
void reset_arrays(void)
{
    /* Clear flags for matrix files */
    w_in_ready = 0;
    w_x_ready = 0;
//    w_out_ready = 0;
    golden_data_out_ready = 0;

    /* Clear static arrays for matrices */
    memset(w_in, 0, sizeof(w_in));
    memset(w_x, 0, sizeof(w_x));
    memset(w_out, 0, sizeof(w_out));
    set_W_out(w_out);
    memset(state_pre, 0, sizeof(state_pre));
    memset(w_out, 0, sizeof(w_out));

    /* Free dynamic data_in if allocated */
    if (data_in != NULL) {
        free(data_in);
        data_in = NULL;
    }
    data_in_count = 0;
    cumulative_mse     = 0.0f;
    cumulative_samples = 0;
    total_samples_processed = 0;

//    clear_output_buffer();

    disable_training();

    xil_printf("Soft reset complete. Arrays cleared.\n\r");
}

/* Reset only the DATAIN array and related flags */
void reset_data_in(void)
{
    if (data_in != NULL) {
        free(data_in);
        data_in = NULL;
    }
    data_in_count = 0;
    total_samples_processed = 0;
    memset(state_pre, 0, sizeof(state_pre));
    cumulative_mse     = 0.0f;
    cumulative_samples = 0;

    xil_printf("DATAIN reset complete. DATAIN array cleared.\n\r");
}


