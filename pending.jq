# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2026 Henrique Almeida <me@h3nc4.com>

# Names every check run that keeps the commit from merging, on one line, since an annotation
# shows only the first line of a notice. Prints an empty line when none does.
[
  .check_runs[]
  | select(
      .status != "completed"
      or (.conclusion as $c | ["success", "skipped", "neutral"] | index($c) | not)
    )
  | "\(.name) is \(.status)/\(.conclusion // "-")"
]
| join(", ")
