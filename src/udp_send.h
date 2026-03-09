#ifndef UDP_SEND_H
#define UDP_SEND_H

#ifdef __cplusplus
extern "C" {
#endif

#include "lwip/udp.h"
#include "lwip/pbuf.h"
#include "esn_main.h"   // For run_esn_calculation(), reset_arrays(), reset_data_in(), etc.
#include "esn_core.h"   // If any ESN functions are needed directly
#include "xil_printf.h"
#include "rls_training.h"
#include <string.h>
#include <stdlib.h>

/* Define the UDP port to be used for data transfer */
#define UDP_TX_PORT 5000



/* Function prototype to start the command server */
void start_tx_application_udp(void);

#ifdef __cplusplus
}
#endif

#endif /* TCP_COMMAND_H */
