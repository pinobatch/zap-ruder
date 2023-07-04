;
; Zapper demo for NES
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

.include "nes.inc"
.include "global.inc"

.import axe_callback_on
.export pently_zp_state

.segment "ZEROPAGE"
nmis:          .res 1
oam_used:      .res 1  ; starts at 0
cur_keys:      .res 2
new_keys:      .res 2

; Used by music engine
pently_zp_state: .res 32


.segment "INESHDR"
  .byt "NES",$1A  ; magic signature
  .byt 1          ; PRG ROM size in 16384 byte units
  .byt 1          ; CHR ROM size in 8192 byte units
  .byt $01        ; mirroring type and mapper number lower nibble
  .byt $00        ; mapper number upper nibble

FOR_ACTION53 = 1

.segment "VECTORS"
.proc allvectors
e0:
.if ::FOR_ACTION53
  jmp tennis_only
  jmp axe_only
  jmp calibration_only
.endif
  .res e0+$1A-*
fa:
.addr nmi, reset, irq
.endproc

.segment "CODE"
;;
; Notify the main thread that NMI has occurred.  (There aren't any
; scroll splits or the like that'd need a more complex NMI handler.)
.proc nmi
  inc nmis
  rti
.endproc

; IRQ handler that does nothing so that BRK $00 can be a breakpoint
.proc irq
  rti
.endproc

.if ::FOR_ACTION53
; Ordinarily I put it at $07FF, but MineShaft has some sort of
; stack at $07FF. Fortunately, it only ever uses about 16 bytes
; during gameplay, so I'll allow 32.
mineshaft_zapruder_nmi_switch = $07DF
.proc tennis_only
  sei
  ldx #$FF
  txs
  stx mineshaft_zapruder_nmi_switch
  inx
  stx axe_callback_on
  jsr pently_init
  jsr tennis
  jmp ($FFFC)
.endproc

.proc axe_only
  sei
  ldx #$FF
  txs
  stx mineshaft_zapruder_nmi_switch
  inx
  stx axe_callback_on
  jsr pently_init
  jsr axe
  jmp ($FFFC)
.endproc

.proc calibration_only
  sei
  ldx #$FF
  txs
  stx mineshaft_zapruder_nmi_switch
  inx
  stx cur_hue
  stx PPUCTRL
  stx PPUMASK
  lda #6
  sta cur_bright
  lda #$3F
  sta PPUADDR
  stx PPUADDR
palloop:
  lda initial_palette,x
  sta PPUDATA
  inx
  cpx #32
  bcc palloop

  jsr pently_init
  jsr test_fullbright_yonoff
  jmp ($FFFC)
.endproc
.endif

.proc reset
  ; Put all sources of interrupts into a known state.
  sei             ; Disable interrupts
  ldx #$00
  stx PPUCTRL     ; Disable NMI and set VRAM increment to 32
  stx PPUMASK     ; Disable rendering
  stx $4010       ; Disable DMC IRQ
  dex             ; Subtracting 1 from $00 gives $FF, which is a
  txs             ; quick way to set the stack pointer to $01FF
  bit PPUSTATUS   ; Acknowledge stray vblank NMI across reset
  bit SNDCHN      ; Acknowledge DMC IRQ
  lda #$40
  sta P2          ; Disable APU Frame IRQ
  lda #$0F
  sta SNDCHN      ; Disable DMC playback, initialize other channels

vwait1:
  bit PPUSTATUS   ; It takes one full frame for the PPU to become
  bpl vwait1      ; stable.  Wait for the first frame's vblank.

  ; We have about 29700 cycles to burn until the second frame's
  ; vblank.  Use this time to get most of the rest of the chipset
  ; into a known state.

  cld  ; just in case running on a famiclone with working decimal hw
  
  ; jmp calibration_only

  ; Clear OAM and the zero page here.
  ldx #0
  jsr ppu_clear_oam  ; clear out OAM from X to end and set X to 0
  txa
clear_zp:
  sta $00,x
  inx
  bne clear_zp
  jsr pently_init

vwait2:
  bit PPUSTATUS  ; After the second vblank, we know the PPU has
  bpl vwait2     ; fully stabilized.
  
  ; There are two ways to wait for vertical blanking: spinning on
  ; bit 7 of PPUSTATUS (as seen above) and waiting for the NMI
  ; handler to run.  Before the PPU has stabilized, you want to use
  ; the PPUSTATUS method because NMI might not be reliable.  But
  ; afterward, you want to use the NMI method because if you read
  ; PPUSTATUS at the exact moment that the bit turns on, it'll flip
  ; from off to on to off faster than the CPU can see.

  ; Now the PPU has stabilized, we're still in vblank.  Copy the
  ; palette right now because if you load a palette during forced
  ; blank (not vblank), it'll be visible as a rainbow streak.

  ; Set up game variables, as if it were the start of a new level.
  lda #0
  sta axe_callback_on
  sta cur_hue
  sta axe_callback_on
  lda #6
  sta cur_bright
  lda #4
  sta cur_radius
  
  jsr title_screen

forever:
  jsr pointat_menu
  jsr menu_dispatch
  jmp forever
.endproc

.proc menu_dispatch
  asl a
  tax
  lda menu_item_procs+1,x
  pha
  lda menu_item_procs,x
  pha
  rts

nothing:
  rts
.pushseg
.segment "RODATA"
menu_item_procs:
  .addr test_fullbright_yonoff-1
  .addr test_fullbright_yon2p-1
  .addr test_fullbright_xyon-1
  .addr test_ball_yonoff-1
  .addr test_vlines_yonoff-1
  .addr test_hlines_yonoff-1
  .addr test_trigger_time-1
  .addr axe-1
  .addr tennis-1
  .addr nothing-1
.popseg
.endproc

RIGHT_ARROW_SPRITE_TILE = $06
DOWN_ARROW_SPRITE_TILE = $07

;;
; @param Y vertical position
; @param X horizontal position
; @param A bit 7 on: draw right
.proc draw_y_arrow_sprite
ypos = 0
tilepos = 1
flip = 2
xpos = 3

  stx xpos
  ldx oam_used
  sta OAM+2,x
  tya
  sec
  sbc #4
  sta OAM,x
  lda #RIGHT_ARROW_SPRITE_TILE
  sta OAM+1,x
  lda xpos
  sta OAM+3,x
  txa
  clc
  adc #4
  sta oam_used
  rts
.endproc

;;
; @param Y vertical position
; @param X horizontal position
; @param A bit 6 on: draw right
.proc draw_x_arrow_sprite
ypos = 0
tilepos = 1
flip = 2
xpos = 3
  cpx #3
  bcs nope
  ldx #3
nope:

  stx xpos
  ldx oam_used
  sta OAM+2,x
  dey
  tya
  sta OAM,x
  lda #DOWN_ARROW_SPRITE_TILE
  sta OAM+1,x
  lda xpos
  sec
  sbc #3
  sta OAM+3,x
  txa
  clc
  adc #4
  sta oam_used
  rts
.endproc


.segment "CHR"
.incbin "obj/nes/bggfx.chr"
.incbin "obj/nes/spritegfx.chr"
