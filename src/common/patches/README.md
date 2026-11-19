https://github.com/android-rpi/device_arpi_rpi4/wiki/Android-10-:-patch-framework-source

## Patch files

- `android-<version>.patch`: for RPi. `android-<version>-generic.patch`: for
  non-RPi (cuttlefish and the emulator). `patcher.sh --set` selects them.
- `patcher.sh` applies every file of the set found under this directory, in
  the directory of the file. The paths in a file are relative to it, e.g.
  `device/generic/goldfish/android-14-generic.patch` has
  `./board/kernel/x86_64.mk`.
- Each file is judged separately (applied, not applied, or an error if
  partially applied). Add a new file instead of new hunks to an existing file
  when old workdirs have the existing file applied: they get the new file by
  running `patch` again.
- `make_patch.sh` (`src/host/make_patch.sh`, run on the host) writes only the
  top-level file (`android-<version>*.patch`).
  Make a patch file in a subdirectory by hand, e.g.
  `diff -U 5 --label ./board/kernel/x86_64.mk --label ./board/kernel/x86_64.mk <orig> <new>`.
  When remaking the top-level file by `make_patch.sh`, do not leave
  `*.patched` of the files of the subdirectory patches in the tree (e.g. by
  `patcher.sh --make-patched`); they are mixed into the top-level file.
