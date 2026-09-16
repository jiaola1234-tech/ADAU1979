# ADAU1979 Vivado Files

This folder contains the Vivado-side files for replacing the original AD7606
capture block with the ADAU1979 capture IP.

Before powering the board, set unique I2C addresses. Remove `R11.0/R12.0` for
U1 address `0x11`; remove `R11.1/R14.1` for U2 address `0x31`. The schematic
otherwise biases every ADDR pin to about 1.65 V and both devices cannot be
configured independently on the shared bus.

## Recommended Flow

Run this from a fresh Vivado Tcl Console:

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/01_clone_and_patch_ad7606_project.tcl
```

It will:

1. Package `C:/Users/weitong/Desktop/ADAU1979/ip_repo/adau1979_capture_1.0`.
2. Open the original project:

```text
C:/Users/weitong/Desktop/finalversion/vivado/ad7606_lwip.xpr
```

3. Save a new project under:

```text
C:/Users/weitong/Desktop/ADAU1979/vivado/adau1979_lwip/adau1979_lwip.xpr
```

4. Disable the old `ad7606.xdc`.
5. Add the AX7020 J11 ADAU1979 constraint file.
6. Replace `ad7606_sample_0` with `adau1979_capture_0` in `design_1.bd`.
7. Set `axi_dma_0` S2MM stream width to 256 bits.
8. Connect AXI-Lite, AXI-Stream, clock, reset, and external ADAU1979 pins.

The script will stop if the destination project directory already exists. Rename
or remove that generated directory before running it again.

## Separate Steps

Package the IP only:

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/00_package_adau1979_ip.tcl
```

Replace the block design in the currently opened project:

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/02_replace_ad7606_with_adau1979_bd.tcl
```

Check the generated/opened project:

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/03_check_adau1979_project.tcl
```

Build bitstream and export XSA for Vitis:

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/04_build_bitstream_and_export_xsa.tcl
```

Run an out-of-context synthesis check for the IP:

```tcl
source C:/Users/weitong/Desktop/ADAU1979/scripts/check_adau1979_ip_synth.tcl
```

## Pin Constraint

The AX7020 J11 constraint file is:

```text
C:/Users/weitong/Desktop/ADAU1979/vivado/constraints/ax7020_adau1979_j11.xdc
```

It assumes the ADAU1979 board is wired like this:

```text
ADAU1979 H4-1 SCL        -> AX7020 J11-3  F17 -> adau_scl
ADAU1979 H4-2 SDA        -> AX7020 J11-4  F16 -> adau_sda
ADAU1979 H4-3 BCLK       -> AX7020 J11-5  F20 -> adau_bclk
ADAU1979 H4-4 LCLK/LRCLK -> AX7020 J11-6  F19 -> adau_lrclk
ADAU1979 H4-5 SDATAOUT02 -> AX7020 J11-7  G20 -> adau_sdata[1]
ADAU1979 H4-6 SDATAOUT01 -> AX7020 J11-8  G19 -> adau_sdata[0]
ADAU1979 H4-7 SDATAOUT12 -> AX7020 J11-9  H18 -> adau_sdata[3]
ADAU1979 H4-8 SDATAOUT11 -> AX7020 J11-10 J18 -> adau_sdata[2]
ADAU1979 H4-9 PD/RST     -> AX7020 J11-11 L20 -> adau_pd_rst
ADAU1979 H4-10 GND       -> AX7020 J11 GND
```

J11 is 3.3 V IO. Do not connect 5 V logic to these pins.

## After Script Runs

In Vivado:

1. Open `design_1.bd`.
2. Run `source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/03_check_adau1979_project.tcl`.
3. Generate Output Products.
4. Create or regenerate HDL wrapper.
5. Run Synthesis and Implementation.
6. Generate bitstream.
7. Export hardware with bitstream to Vitis.

Or run:

```tcl
source C:/Users/weitong/Desktop/ADAU1979/vivado/scripts/04_build_bitstream_and_export_xsa.tcl
```

If constraints complain about missing ports, run this in Tcl Console:

```tcl
get_ports *adau*
```

Then adjust the port names in the XDC if Vivado generated names such as
`adau_bclk_0`.
