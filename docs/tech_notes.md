Zap Ruder technical notes
=========================

The menu
--------

The menu works by measuring the height of the brightness and then
turning off the rectangles for group 1 (items on the left) and group
2 (items on the right) in sequence.

Gun states:

- `POINTAT_NOTHING`  
  Gun is pointed at blackness.
  When brightness is detected, darken group 1 and go to `POINTAT_TESTGRP1`.
- `POINTAT_TESTGRP1`
  Group 1 is black.
  If brightness is not detected, show all groups, freeze Y, and go to `POINTAT_GRP1`.
  Otherwise, show group 1, darken group 2, and go `POINTAT_TESTGRP2`.
- `POINTAT_TESTGRP2`  
  Group 2 is black.
  If brightness is not detected, show all groups, freeze Y, and go to `POINTAT_GRP2`.
  Otherwise, show all groups and go to `POINTAT_NOTHING`.
- `POINTAT_GRP1`  
  Within a group 1 item's rectangle.
  When brightness is no longer detected or Y has moved far, go to `POINTAT_NOTHING`.
- `POINTAT_GRP2`  
  Within a group 2 item's rectangle.
  When brightness is no longer detected or Y has moved far, go to `POINTAT_NOTHING`.
- `POINTAT_NONTARGET`  
  Gun is pointed at brightness, but not one of the targets.
  When brightness is no longer detected, go to `POINTAT_NOTHING`.

The kernel
-----------

There are three "kernels", or cycle-timed loops, for reading the
Zapper's photosensor.  They synchronize to the horizontal retrace
period of 113.667 cycles per line, which is valid on Famicom, NTSC
NES, NTSC famiclones, and Dendy-style PAL famiclones (but not the
authentic PAL NES).  Each measures how many scanlines from the start
of the kernel (use sprite 0 to align this) to when the Zapper's
photosensor turns on, as a way of estimating how far down the screen
the barrel is pointed.  In my tests, this vertical position changes
at least as smoothly as the Wii Remote's position.

### `yonoff`

- Polls port 2
- Returns Y position and height of brightness

This is the most common kernel.  It measures how many scanlines
elapse before the photosensor in the gun on controller port 2 turns
on and how many before it turns back off.

An empty controller port or standard controller will have zero off
time and a maximum on time.  A Zapper plugged in and not pointed at
brightness will have maximum off time and zero on time.  When a
Zapper is pointed at brightness, the on time may range from 4 to 28
depending on the brightness of the area in front of the barrel.

### `yon2p`

- Polls ports 1 and 2
- Returns two Y positions

This kernel measures how many scanlines before the photosensor in
the gun on each of the two controller ports turns on.  This kernel
does not measure on time.  An unplugged gun can be detected with
a zero off time that stays zero even during vertical blank.

### `xyon`

- Polls port 2
- Returns X and Y position

This was an attempt to measure down to an 18-pixel level at what
point across the screen the photosensor on the gun in controller port
2 turns on.  On some emulators, it works as advertised, but on an
actual NES and TV, there are several dozen pixels of noise added.
So it's probably only good for detecting left, middle, or right,
not for (say) lobbing a grenade at the point where the player shot.

Color calibration
-----------------

Brightnesses 0 through 8 in the user interface are translated into
NES colors:

- Color 1 is (((bright - 0) << 3) & 0xF0) | hue
- Color 2 is (((bright - 1) << 3) & 0xF0) | hue

Examples:

- bright 0 hue 3 is $03 and $F3 (becomes $0F)
- bright 5 hue 5 is $25 and $25
- bright 8 hue 7 is $47 (becomes $30) and $37

Values $40 and up saturate at white ($30); negative colors ($Fx)
saturate at black ($0F).

On my TV, brightnesses 5 and 7 of any hue (NES colors $2x and $3x)
reliably turn on the photosensor.  On brightness 3 ($1x), it appears
hues 6 (red) through 8 (brown/yellow) are the weakest.

Collision response between ball and paddle
------------------------------------------

The ball in ZapPing can collide with only one paddle at once, based
on the sign of the horizontal component of the velocity.  If it is
going to the right, it is tested against only the right player's
paddle; if to the left, against the left player's.  It moves
the ball twice each frame and checks for collision twice so that the
ball does not move through the paddle even at speeds up to 20 pixels
per frame.

The collision code divides the paddle into three segments: a
semicircle at the top with the same radius as the ball, a rectangle,
and another semicircle at the bottom.  After trivial rejection with
the bounding boxes of the ball and paddle, the ball's vertical
position determines which section is tested against.  Tests against
the rectangle are easy; tests against the semicircles result in
collision if the sum of squares of X and Y distances are less than
the square of the sum of the radii of the semicircle and ball.

Now as for collision response:  Let [Tau] be the number of radians
in a circle, or twice Pi.  Let one angle unit, symbol *b*, represent
Tau/32 radians or 11.25 degrees, as a [binary fraction of a turn].

        v------- 6b
      ,---.
     /   ,'\  <- 5b
    |---o---|
    |       | <- 4b
    |       |

A ball hitting the rectangular flat part of the paddle bounces at
between *b* and 4*b* (up to 45 degrees up) depending on the distance
from dead center.  (A ball hitting dead center will intentionally not
bounce at dead center because that would make the game too easy.)
A ball hitting the 45 degrees at the front of each semicircle bounces
at 5*b*; a ball hitting the rest of the semicircle bounces at 6*b*.
Cosine and sine values of this angle are pulled from a sine lookup
table and multiplied by the current game speed giving the ball's
velocity.

The ball's speed is measured in units of pixels per 32 frames, or
1/16 pixel per half frame.  It decreases somewhat after each miss and
then increases after each bounce: by 1/32 of the peak speed if the
current speed is less than the peak speed seen during the game, or by
2 units (1/8 pixel per half-frame) if the current speed is at peak.

[Tau]: https://tauday.com/
[binary fraction of a turn]: https://en.wikipedia.org/wiki/Binary_angular_measurement

Computer opponent
-----------------

The AI in ZapPing models the path of the ball using the
slope-intercept equation of a line:

> *y* = *mx* + *b*

In this equation:

- *y* is vertical position
- *m* is the slope of a line
- *x* is the horizontal displacement from the origin
- *b* is the value of *y* when *x* = 0

The slope of a line between two points is the rise, or vertical part
of the displacement between the points, divided by the run, or
horizontal part.  A velocity vector in 2-space has a slope too; in
fact, a vector can be fully defined by its slope and its speed.
The computer opponent code in ZapPing uses the slope of the velocity
vector to determine where the ball is headed, and it calculates thus:

1. Reflect the vector into the first quadrant
2. Shift the horizontal part of the velocity right until it is below
   256, and count the shifts
3. Shift the vertical part of the speed right until it is less than
   the horizontal part, and count the shifts
4. Divide the shifted vertical part by the shifted horizontal part
   in 0.8 fixed point, giving a shifted slope
5. Multiply this shifted slope by the horizontal part of the distance
   from the ball to the paddle, giving 2<sup>*s*</sup>*mx*
6. Shift the result right by
   8 + (number of horizontal shifts) - (number of vertical shifts)
   giving the absolute displacement |*mx*|
7. Reflect the displacement based on the sign of the vertical part,
   giving the displacement *mx*
8. Add the current vertical displacement of the ball, giving the
   end displacement *mx* + *b*
9. Reflect against the walls, giving a predicted destination

This would be a lot easier on a PC or smartphone with floating-point
arithmetic.  On a machine with an 8-bit CPU, we don't have such
luxuries.  Still, in a way, the accumulated [shift count] to get the
components in range for the division behaves like the exponent in
software floating-point.

The paddle moves toward the prediction.  I didn't want the paddle to
"teleport" atop the prediction but instead move as if a player were
moving the paddle using a controller.  So I used the upper 8 bits of
the paddle's velocity to look up approximate braking distances in a
lookup table.  Every frame, it compares the predicted ball
position to the predicted paddle position.  If the predictions differ
by more than one quarter of a paddle length, the AI moves the paddle
toward the ball.

[shift count]: https://en.wikipedia.org/wiki/Fixed-point_arithmetic#Scaling_and_renormalization
