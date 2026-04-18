#pragma once

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void ue_reflect_button_press(id buttonInput);

void ue_reflect_button_release(id buttonInput);

void ue_reflect_thumbstick(id directionPad, float x, float y);

id ue_get_extended_gamepad(id virtualController);

id ue_get_button(id gamepad, NSString *element);

id ue_get_thumbstick(id gamepad, NSString *element);

void ue_init_gyro_hooks(void);

void ue_apply_gyro_velocity(double vx, double vy);

void ue_reset_gyro_context(void);

#ifdef __cplusplus
}
#endif
