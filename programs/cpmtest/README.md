# CPMTEST

Exercises file creation, sequential writes/reads, random reads, size, and
deletion on A: using a 75 KiB file. Intended to check the SD filesystem.

Run `CPMTEST` on A:. It replaces `A:CPMTEST.DAT` in the current user area.
Escape then C cancels between records; cancellation retains the partial file.
