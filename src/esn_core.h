#ifndef ESN_CORE_H
#define ESN_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

#include <math.h>
#include <stdint.h>

/*
 * Adjust NUM_INPUTS, NUM_OUTPUTS and NUM_NEURONS here,
 */
#define NUM_INPUTS  128   /* data input size */
#define NUM_OUTPUTS 128	 /* data output size */
#define NUM_NEURONS 8    /* reservoir (hidden) layer size */

#define EXTENDED_STATE_SIZE (NUM_INPUTS + NUM_NEURONS)

/*
 * Adjust Fraction bits for approximation here
 */

#define state_pre_frac 19
#define W_in_frac 15
#define dataIn_frac 15
#define W_x_frac 15

#define state_extended_frac 19
#define W_out_frac 15

#define predicted_frac 19


/*
 * update_state()
 *   - W_in:    Flattened input weight matrix of size (NUM_NEURONS * NUM_INPUTS)
 *   - dataIn:  Array of size NUM_INPUTS
 *   - W_x:     Flattened recurrent weight matrix of size (NUM_NEURONS * NUM_NEURONS)
 *   - state_pre: The previous reservoir state (size NUM_NEURONS)
 *   - state:   The new updated reservoir state (size NUM_NEURONS)
 */
void update_state(const float *W_in,
                  const float *dataIn,
                  const float *W_x,
                  const float *state_pre,
                  float *state);


/*
 * update_state_fx()
 *   - W_in:    Flattened input weight matrix of size (NUM_NEURONS * NUM_INPUTS)
 *   - dataIn:  Array of size NUM_INPUTS
 *   - W_x:     Flattened recurrent weight matrix of size (NUM_NEURONS * NUM_NEURONS)
 *   - state_pre: The previous reservoir state (size NUM_NEURONS)
 *   - state:   The new updated reservoir state (size NUM_NEURONS)
 */
void update_state_fx(const float *W_in,
                  const float *dataIn,
                  const float *W_x,
                  const float *state_pre,
                  float *state);

/*
 * form_state_extended()
 *   - dataIn:  input vector (size NUM_INPUTS)
 *   - state:   reservoir state (size NUM_NEURONS)
 *   - state_extended: an output array of size (NUM_NEURONS + NUM_INPUTS)
 *       which combines (state + input) for computing output layer
 */
void form_state_extended(const float *dataIn,
                         const float *state,
                         float *state_extended);

/*
 * compute_output()
 *   - W_out:  Flattened output weight matrix of size:
 *             (output_dim * (NUM_INPUTS + NUM_NEURONS))
 *             If your ESN’s output is 4 floats, that means 4 * (NUM_INPUTS + NUM_NEURONS).
 *   - state_extended: The extended state array (size NUM_INPUTS + NUM_NEURONS)
 *   - data_out: The ESN's output vector
 *       (size is however many output neurons you have, e.g., 4).
 */
void compute_output(const float *W_out,
                    const float *state_extended,
                    float *data_out);


/*
 * compute_output_fx()
 *   - W_out:  Flattened output weight matrix of size:
 *             (output_dim * (NUM_INPUTS + NUM_NEURONS))
 *             If your ESN’s output is 4 floats, that means 4 * (NUM_INPUTS + NUM_NEURONS).
 *   - state_extended: The extended state array (size NUM_INPUTS + NUM_NEURONS)
 *   - data_out: The ESN's output vector
 *       (size is however many output neurons you have, e.g., 4).
 */
void compute_output_fx(const float *W_out,
                    const float *state_extended,
                    float *data_out);

float compute_mse(const float *predicted,
				  const float *golden,
				  int length);

float compute_mse_fx(const float *predicted,
				  const float *golden,
				  int length);

#ifdef __cplusplus
}
#endif

#endif /* ESN_CORE_H */
