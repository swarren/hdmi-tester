This project implements a simple HDMI test device. The intent is to allow
validation that an HDMI source under test is sending a valid HDMI signal,
and that the signal has the expected properties. This can validate both
the HDMI source hardware, as well as any driver/software stack present on
the device. This may be useful for automated driver regression testing.

Intended features are:

* Attach to an HDMI source, act as an HDMI sink, and provide measurement
  of various HDMI signal properties:
  - HDMI clock (implemented)
  - HDMI VSYNC and HSYNC frequency, polarity, and pulse width.
  - ? Measurement of active video area.
  - ? Analysis of active video data. Checksum? QR/... code extraction?

* Attach to a control device to allow:
  - Download of EDID content to provide over the HDMI port (implemented).
  - Control over the HDMI HPD (hoptplug) signal (implemented).
  - Retrieval of signal measurements (implemented for implemented
    measurements)

Currently, this project targets the Scarab Hardware[1] miniSpartan6+[2]
FPGA board, since that's what I have. I've modified the board so that
the HDMI HPD line is driven directly by an FPGA output, rather than
hard-connected to the source's HDMI +5V line. This allows control over
the HPD signal.

Limitations:

Unfortunately, it looks like the Spartan6 PLLs can't run fast enough to
generate the HDMI bit (not pixel) clock for a max-rate HDMI pixel clock
(165MHz pixel clock -> 1650MHz bit clock). I'm investigating whether the
SERDES block can run in DDR rather than SDR mode to work around this.
Either way, this board is enough to prototype the idea.

[1] http://www.scarabhardware.com/
[2] http://www.scarabhardware.com/product/minispartan6-with-spartan-6-lx-25/
