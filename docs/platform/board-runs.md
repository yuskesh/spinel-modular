# Runs on boards

No test suite in this repository runs an image on a board.
`tests/bare-full/run.sh` runs whole programs for `an521` under QEMU's
`mps2-an521`. The one real board `tools/bare-full` has a board file for,
the FRDM-MCXN947, has been run by hand; this page says what was run, how,
and what was observed. A run of a board whose chip family is kept outside
this repository is recorded with that family.

The programs are those of `tests/bare-full/programs`, built on Debian 13.
The image sizes are of the builds that were run; a later build of the same
program differs in size.

## FRDM-MCXN947 (Cortex-M33)

Built with `--board frdm-mcxn947`, with no RTOS and nothing of the vendor's
SDK in the image. Each flash image was written at 0x10000000 with
LinkServer, as `tests/freestanding/frdm-host.sh` writes the `bare-frdm`
lane's image, its sha256 checked after the copy, and the console (the
MCU-Link VCOM, 115200 8N1) was read from a probe reset.

| Program | Image (text / data / bss) | Console |
|---|---|---|
| `basics.rb` | 253,556 / 1,180 / 45,440 B | its `.out` exactly, `GC 0`, `EXIT 0` |
| `float.rb` | 195,508 / 772 / 33,328 B | its `.out` exactly, `GC 0`, `EXIT 0` |
| `gc.rb` | 209,200 / 1,100 / 70,848 B | its `.out` exactly, `GC 43`, `EXIT 0` |
| `oom.rb`, `--heap-kb 64` | 177,784 / 772 / 43,816 B | `unhandled exception: out of memory`, `GC 3`, `EXIT 1` |

- `gc.rb`'s heap on the board is 222,976 B, and it collects the same 43
  times as on QEMU.
- The clock line is the same in all four: `SCG_CSR=0x03000000` (the system
  clock from FIRC), `FIRCCFG=0x00000000` (48 MHz), `AHBCLKDIV=0x00000000`
  (divided by 1): 48 MHz.
- Not tried: a power-on boot, as opposed to the probe's reset.
- These runs were made before the board's code was divided into a chip
  family and a board file. The board has not been run since; its flash
  image is byte-identical across that change and every later one.
