/*******************************************************************************
 * File: esn_core.c
 * Author: Christopher Boerner
 * Date: 04-01-2025
 *
 * 	 Description:
 *	   Echo State Network (ESN) core equations to perform on the arrays passed
 *	   from tcp_file.c. Currently for one sample.
 *
 *   Expected Files:
 *     - DATAIN file: 40 float values.
 *     - WIN file: 320 float values.
 *     - WX file:  64 float values.
 *     - WOUT file: 192 float values.
 *
 *   Generate:
 *     - state_pre
 *     - res_state
 *     - state_ext
 *     - data_out
 *
 ******************************************************************************/

#include "esn_core.h"
#include <string.h>

void float_approx_array(float *input, float *output, int frac, int array_sz){
	float scale = (float)(1 << frac);

	for(int i = 0; i < array_sz; i++){

		float input_sign = (input[i] >= 0.0f) ? 1.0f : -1.0f;

		float fx_disp = fabsf(input[i]) * scale;   // |a| * 2^frac
		fx_disp = floorf(fx_disp);          // approximate(...)

		output[i] = fx_disp / scale; // back to float
		output[i] *= input_sign;                   // restore sign
	}

}
uint32_t float_to_fixed(float array, int frac){
	return array * ((float)(1 << frac)); //float * 2^frac
}

/*
 * Update reservoir state based on:
 *   state(i) = tanh( W_in(i,:)*dataIn + W_x(i,:)*state_pre )
 */

void update_state(const float *W_in,
                  const float *dataIn,
                  const float *W_x,
                  const float *state_pre,
                  float *state)
{
    float temp1[NUM_NEURONS] = {0};
    float temp2[NUM_NEURONS] = {0};

    /* temp1[i] = sum_j( W_in[i * NUM_INPUTS + j] * dataIn[j] ) */
    for (int i = 0; i < NUM_NEURONS; i++) {
        for (int j = 0; j < NUM_INPUTS; j++) {
            temp1[i] += W_in[i * NUM_INPUTS + j] * dataIn[j];
        }
    }

    /* temp2[i] = sum_j( W_x[i * NUM_NEURONS + j] * state_pre[j] ) */
    for (int i = 0; i < NUM_NEURONS; i++) {
        for (int j = 0; j < NUM_NEURONS; j++) {
            temp2[i] += W_x[i * NUM_NEURONS + j] * state_pre[j];
        }
    }

    /* state[i] = tanh(temp1[i] + temp2[i]) */
    for (int i = 0; i < NUM_NEURONS; i++) { //Don't change to fixed point
        float sum_val = temp1[i] + temp2[i];
        /* Use tanhf for single-precision float math.
           If you're using double math, use tanh(). */
        state[i] = tanh(sum_val);
    }
}

/*
 * Update reservoir state (IN FIXED POINT PRECISION) based on:
 *   state(i) = tanh( W_in(i,:)*dataIn + W_x(i,:)*state_pre )
 */
void update_state_fx(const float *W_in,
                  const float *dataIn,
                  const float *W_x,
                  const float *state_pre,
                  float *state)
{
    float temp1[NUM_NEURONS] = {0};
    float temp2[NUM_NEURONS] = {0};
    //CONVERT INPUTS INTO FX format

    //state_pre: Q0.19
    float *state_pre_approx  = malloc(sizeof(float) * NUM_NEURONS);
    float_approx_array(state_pre, state_pre_approx, state_pre_frac, NUM_NEURONS);

    //Others: Q.15
    float *W_in_approx  = malloc(sizeof(float) * NUM_INPUTS * NUM_NEURONS);
    float *dataIn_approx = malloc(sizeof(float) * NUM_INPUTS);
    float *W_x_approx   = malloc(sizeof(float) * NUM_NEURONS * NUM_NEURONS);

    float_approx_array(W_in, W_in_approx, W_in_frac, NUM_NEURONS*NUM_INPUTS);
    float_approx_array(dataIn, dataIn_approx, dataIn_frac, NUM_INPUTS);
    float_approx_array(W_x, W_x_approx, W_x_frac, NUM_NEURONS*NUM_NEURONS);



    //BELOW IS IN FIXED POINT
    /* temp1[i] = sum_j( W_in[i * NUM_INPUTS + j] * dataIn[j] ) */
    for (int i = 0; i < NUM_NEURONS; i++) {
        for (int j = 0; j < NUM_INPUTS; j++) {
            temp1[i] += W_in_approx[i * NUM_INPUTS + j] * dataIn_approx[j];
        }
    }

    /* temp2[i] = sum_j( W_x[i * NUM_NEURONS + j] * state_pre[j] ) */
    for (int i = 0; i < NUM_NEURONS; i++) {
        for (int j = 0; j < NUM_NEURONS; j++) {
            temp2[i] += W_x_approx[i * NUM_NEURONS + j] * state_pre_approx[j];
        }
    }
    ///////////////////////////////////////////////
    /* state[i] = tanh(temp1[i] + temp2[i]) */
    for (int i = 0; i < NUM_NEURONS; i++) { //Don't change to fixed point
        float sum_val = temp1[i] + temp2[i];
        /* Use tanhf for single-precision float math.
           If you're using double math, use tanh(). */
        state[i] = tanh(sum_val);
    }
    free(state_pre_approx);
    free(W_x_approx);
    free(W_in_approx);
    free(dataIn_approx);
}

/*
 * Create the "extended" state vector, which appends
 * the raw inputs to the reservoir state for final output layer.
 *
 * state_extended = [reservoir_state; input_data]
 *
 * so it ends up length (NUM_NEURONS + NUM_INPUTS).
 */
void form_state_extended(const float *dataIn,
                         const float *state,
                         float *state_extended)
{
    /* Copy reservoir state first */
    for (int i = 0; i < NUM_NEURONS; i++) {
        state_extended[i] = state[i];
    }
    /* Then copy input data after that */
    for (int i = 0; i < NUM_INPUTS; i++) {
        state_extended[NUM_NEURONS + i] = dataIn[i];
    }
}

/*
 * Compute ESN output, e.g.:
 *   data_out[k] = sum_j( W_out[k*TOTAL + j] * state_extended[j] )
 *
 * Where TOTAL = (NUM_INPUTS + NUM_NEURONS),
 * and k goes over however many output dimensions you have (i.e., 4).
 */
void compute_output(const float *W_out,
                    const float *state_extended,
                    float *data_out)
{
    // Use the defined macro NUM_OUTPUTS instead of constant 4.
    int output_dim = NUM_OUTPUTS;
    // total = NUM_INPUTS + NUM_NEURONS, e.g., 128 + 8 = 136
    int total = NUM_INPUTS + NUM_NEURONS;

    for (int i = 0; i < output_dim; i++) {
        data_out[i] = 0.0f;
        for (int j = 0; j < total; j++) {
            data_out[i] += W_out[i * total + j] * state_extended[j];
        }
    }
}

/*
 * Compute ESN output IN FIXED POINT PRECISION, e.g.:
 *   data_out[k] = sum_j( W_out[k*TOTAL + j] * state_extended[j] )
 *
 * Where TOTAL = (NUM_INPUTS + NUM_NEURONS),
 * and k goes over however many output dimensions you have (i.e., 4).
 */
void compute_output_fx(const float *W_out,
                    const float *state_extended,
                    float *data_out)
{
    // Use the defined macro NUM_OUTPUTS instead of constant 4.
    int output_dim = NUM_OUTPUTS;
    // total = NUM_INPUTS + NUM_NEURONS, e.g., 128 + 8 = 136
    int total = NUM_INPUTS + NUM_NEURONS;

    //Convert to fixed point

    //W_out : Q15
    float *W_out_approx = malloc(sizeof(float) * total * output_dim);
    float_approx_array(W_out, W_out_approx, W_out_frac, total*output_dim);

    //state_extended : Q0.19
    float *state_extended_approx = malloc(sizeof(float) * total);
    float_approx_array(state_extended, state_extended_approx, state_extended_frac, total);

    for (int i = 0; i < output_dim; i++) {
        data_out[i] = 0.0f;
        for (int j = 0; j < total; j++) {
            data_out[i] += W_out_approx[i * total + j] * state_extended_approx[j];
        }
    }
    free(W_out_approx);
    free(state_extended_approx);
}

/**
 * Computes the Mean Squared Error (MSE) between two arrays of floats.
 *
 * @param predicted  Pointer to the array of predicted (computed) values.
 * @param golden     Pointer to the array of golden (reference) values.
 * @param length     The number of elements in each array.
 * @return           The MSE value as a float.
 */
float compute_mse(const float *predicted, const float *golden, int length)
{
    float mse = 0.0f;
    for (int i = 0; i < length; i++) {
        float diff = predicted[i] - golden[i];
        mse += diff * diff;
    }
    mse /= length;
    return mse;
}

/**
 * Computes the Mean Squared Error (MSE) between two arrays of floats using FIXED POINT PRECISION.
 *
 * @param predicted  Pointer to the array of predicted (computed) values.
 * @param golden     Pointer to the array of golden (reference) values.
 * @param length     The number of elements in each array.
 * @return           The MSE value as a float.
 */
float compute_mse_fx(const float *predicted, const float *golden, int length)
{
	//convert to fixed
	//predicted : q19
	float *predicted_approx = malloc(sizeof(float) * length);
	float_approx_array(predicted, predicted_approx, predicted_frac, length);

    float mse = 0.0f;
    for (int i = 0; i < length; i++) {
        float diff = predicted_approx[i] - golden[i];
        mse += diff * diff;
    }
    mse /= length;
    free(predicted_approx);
    return mse;
}
