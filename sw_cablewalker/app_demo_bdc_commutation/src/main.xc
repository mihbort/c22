/* PLEASE REPLACE "CORE_BOARD_REQUIRED" AND "IFM_BOARD_REQUIRED" WITH AN APPROPRIATE BOARD SUPPORT FILE FROM module_board-support */
#include <CORE_C22-rev-a.inc>
#include <IFM_DC100-rev-b.inc>

/**
 * @brief Test illustrates usage of module_commutation
 * @date 17/06/2014
 */
#include <xs1.h>
#include <platform.h>
#include <pwm_service_inv.h>
#include <commutation_server.h>
#include <brushed_dc_server.h>
#include <brushed_dc_client.h>
#include <refclk.h>
#include <internal_config.h> //FIXME: to use BDC motor, please change the parameter #define MOTOR_TYPE BDC
#include <brushed_dc_common.h>
#include <bldc_motor_config.h>

on tile[IFM_TILE]:clock clk_adc = XS1_CLKBLK_1;
on tile[IFM_TILE]:clock clk_pwm = XS1_CLKBLK_REF;

void set_BDC_motor_voltage(chanend c_commutation, int input_voltage){
    c_commutation <: BDC_CMD_SET_VOLTAGE;
    c_commutation <: input_voltage;
    return;
}

void handle_digital_io(chanend c_commutation, port p_ifm_ext_d[]){
    int cmd_forward, cmd_backward;
    int sp_voltage = 5000;//maximum 13589
    int voltage = 0;
    p_ifm_ext_d[0] :> cmd_forward;
    p_ifm_ext_d[1] :> cmd_backward;

    while(1){
        select{
            //wait for state change on port D0
            case p_ifm_ext_d[0] when pinsneq(cmd_forward) :> cmd_forward:
                if(cmd_forward && !cmd_backward){//D0 logical one
                    for (; voltage < sp_voltage; voltage ++){
                        set_BDC_motor_voltage(c_commutation, voltage);
                    }
                }
                else if(!cmd_forward && !cmd_backward){//logical zero
                    for (; voltage > 0; voltage --){
                        set_BDC_motor_voltage(c_commutation, voltage);
                    }
                }
                break;
            //wait for state change on port D1
            case p_ifm_ext_d[1] when pinsneq(cmd_backward) :> cmd_backward:
                if(cmd_backward && !cmd_forward){//D1 logical one
                    for (; voltage > -sp_voltage; voltage --){
                        set_BDC_motor_voltage(c_commutation, voltage);
                    }
                }
                else if(!cmd_backward && !cmd_forward){//logical zero
                    for (; voltage < 0; voltage ++){
                        set_BDC_motor_voltage(c_commutation, voltage);
                    }
                }
                break;
        }
    }
}

int main(void) {

    // Motor control channels
    chan c_pwm_ctrl, c_adctrig; // pwm channels
    chan c_watchdog;
    chan c_commutation;                     // motor drive channels

    par
    {
        /************************************************************
         * USER_TILE
         ************************************************************/


        /************************************************************
         * IFM_TILE
         ************************************************************/
        on tile[IFM_TILE]:
        {
            par
            {
                /* PWM Loop */
                do_pwm_inv_triggered(c_pwm_ctrl, c_adctrig, p_ifm_dummy_port,\
                        p_ifm_motor_hi, p_ifm_motor_lo, clk_pwm);

                /* Brushed Motor Drive loop */

                bdc_loop(c_watchdog, c_commutation, c_pwm_ctrl,\
                        p_ifm_esf_rstn_pwml_pwmh, p_ifm_coastn, p_ifm_ff1, p_ifm_ff2);


                /* Watchdog Server */
                run_watchdog(c_watchdog, p_ifm_wd_tick, p_ifm_shared_leds_wden);

                handle_digital_io(c_commutation, p_ifm_ext_d);

            }
        }

    }

    return 0;
}
