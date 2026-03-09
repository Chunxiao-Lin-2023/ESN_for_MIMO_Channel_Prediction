/*
 * Copyright (C) 2017 - 2019 Xilinx, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR IMPLIED
 * WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
 * SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
 * OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
 * IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
 * OF SUCH DAMAGE.
 *
 */
/*
 * Modifications by Ahmed Malik, Virginia Tech ECE, 2025.
 * - Only using start_application
 *
 */
/** Connection handle for a UDP Server session */

#include "udp_send.h"

#include "esn_main.h"

static struct udp_pcb *pcb_tx = NULL;

void start_tx_application_udp(void) {
    pcb_tx = udp_new();
    if (!pcb_tx) { xil_printf("TX: cannot alloc pcb\n\r"); return; }

    err_t e = udp_bind(pcb_tx, IP_ADDR_ANY, UDP_TX_PORT);
    if (e != ERR_OK) { xil_printf("TX: bind %u failed %d\n\r", UDP_TX_PORT, e); udp_remove(pcb_tx); pcb_tx=NULL; return; }

    xil_printf("TX server waiting on port %u\n\r", UDP_TX_PORT);
}
