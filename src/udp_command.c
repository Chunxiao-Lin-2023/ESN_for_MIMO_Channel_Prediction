/*******************************************************************************
 * File: udp_command.c
 * Author: Ahmed Malik
 * Date: 09-22-2025
 *
 *   Description:
 *	   Send commands over a separate Ethernet port (5002) to control ESN core.
 *
 *   Commands:
 *     - ESN: Start ESN core computation and generate output.
 *     - RESET: Soft reset all ESN arrays/values.
 *     - RDI: Just reset the data_in.
 *
 ******************************************************************************/

#include "lwip/udp.h"
#include "lwip/pbuf.h"
#include "lwip/ip_addr.h"
#include "lwip/inet.h"
#include <string.h>
#include <stdio.h>

/* Your existing headers that declare these helpers and constants */
#include "udp_command.h"      // if it has CMD_PORT / CMD_BUF_SIZE
#include "esn_main.h"         // reset_arrays(), reset_data_in(), etc.
#include "xil_printf.h"



/* ------------------------------------------------------------------ */
/* Small helper to reply to the sender                                */
/* ------------------------------------------------------------------ */
void udp_cmd_send_reply(struct udp_pcb *pcb, const ip_addr_t *addr, u16_t port,
                        const char *msg)
{
    if (!pcb || !addr || !msg) return;

    u16_t len = (u16_t)strlen(msg);
    struct pbuf *rp = pbuf_alloc(PBUF_TRANSPORT, len, PBUF_RAM);
    if (!rp) return;

    memcpy(rp->payload, msg, len);
    udp_sendto(pcb, rp, addr, port);
    pbuf_free(rp);
}

/* ------------------------------------------------------------------ */
/* UDP receive callback (one call per datagram)                        */
/* Signature must match lwIP's udp_recv_fn                             */
/* ------------------------------------------------------------------ */
static void udp_cmd_recv_cb(void *arg,
                            struct udp_pcb *pcb,
                            struct pbuf *p,
                            const ip_addr_t *addr,
                            u16_t port)
{
    if (!p) return;// Defensive; UDP typically passes a valid p


    if (p->tot_len == 0) { pbuf_free(p); return; } //Optional: ignores empty payloads

    /* Copy payload into a local, NUL-terminated buffer */
    char cmd_buf[CMD_BUF_SIZE];
    u16_t to_copy = (p->tot_len < (CMD_BUF_SIZE - 1)) ? p->tot_len : (CMD_BUF_SIZE - 1);
    pbuf_copy_partial(p, cmd_buf, to_copy, 0);  // works even if p is a chain
    cmd_buf[to_copy] = '\0';

    xil_printf("UDP command from %s:%u -> \"%s\"\r\n",
               ipaddr_ntoa(addr), port, cmd_buf); //print sender address


    /* Parse commands (same logic as TCP version) */
    if (strncmp(cmd_buf, "RESET", 5) == 0) {
        reset_arrays();
        udp_cmd_send_reply(pcb, addr, port, "OK RESET");
    }
    else if (strncmp(cmd_buf, "RDI", 3) == 0) {
        reset_data_in();
        udp_cmd_send_reply(pcb, addr, port, "OK RDI");
    }
    else if (strncmp(cmd_buf, "TRN_ON", 6) == 0) {
        enable_training();
        udp_cmd_send_reply(pcb, addr, port, "OK TRN_ON");
    }
    else if (strncmp(cmd_buf, "TRN_OFF", 7) == 0) {
        disable_training();
        udp_cmd_send_reply(pcb, addr, port, "OK TRN_OFF");
    }
    else {
        xil_printf("Unknown UDP command.\r\n");
        udp_cmd_send_reply(pcb, addr, port, "ERR UNKNOWN");
    }

    /* IMPORTANT: free the incoming datagram */
    pbuf_free(p);
}

/* ------------------------------------------------------------------ */
/* Server start (bind + register callback). No listen/accept for UDP.  */
/* ------------------------------------------------------------------ */
void start_command_server_udp(void)
{
    struct udp_pcb *pcb = udp_new_ip_type(IPADDR_TYPE_ANY);
    if (!pcb) {
        xil_printf("UDP cmd: failed to create PCB\r\n");
        return;
    }

    err_t err = udp_bind(pcb, IP_ADDR_ANY, CMD_PORT);
    if (err != ERR_OK) {
        xil_printf("UDP cmd: bind to port %d failed, err=%d\r\n", CMD_PORT, err);
        udp_remove(pcb);
        return;
    }

    udp_recv(pcb, udp_cmd_recv_cb, NULL);

    xil_printf("Command server (UDP) listening on port %d\r\n", CMD_PORT);
}
