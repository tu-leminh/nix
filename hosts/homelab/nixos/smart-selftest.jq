# Prometheus textfile metrics for SMART self-tests, from an array of
# `smartctl -j -a` outputs (one per disk). Read by node-exporter's textfile
# collector (argohome apps/infra/monitoring).
#
# Status codes, per smartmontools ataprint.cpp / nvmeprint.cpp:
#   ATA  status byte, high nibble: 0 ok, 1-2 aborted, 3-8 failed, 0xf running
#   NVMe result: 0 ok, 5-7 failed, everything else aborted
# Both logs are newest first.

def esc: tostring | gsub("\\\\"; "\\\\") | gsub("\""; "\\\"") | gsub("\n"; " ");

def kind($code): ($code % 128) as $c
  | if $c == 1 then "short" elif $c == 2 then "long" else "other" end;

# Every logged test as {type, state, age_hours}. ATA logs a 16-bit lifetime
# hour counter, so its age is taken modulo 65536. Some firmware (WD Blue SSD)
# logs a running test as completed at hour 0 and fills in the hour when it
# finishes; those entries are skipped.
def tests: .power_on_time.hours as $poh
  | ((.ata_smart_self_test_log.standard.table // [])
      | map(select(.lifetime_hours > 0))
      | map({ type: kind(.type.value),
              state: ((.status.value / 16 | floor) as $n
                      | if $n == 0 then "ok"
                        elif $n >= 3 and $n <= 8 then "failed"
                        else "aborted" end),
              age_hours: (($poh % 65536) - .lifetime_hours + 65536) % 65536 }))
  + ((.nvme_self_test_log.table // [])
      | map({ type: kind(.self_test_code.value),
              state: (.self_test_result.value as $r
                      | if $r == 0 then "ok"
                        elif $r >= 5 and $r <= 7 then "failed"
                        else "aborted" end),
              age_hours: ($poh - .power_on_hours) }));

def running:
  if .nvme_self_test_log then
    (.nvme_self_test_log.current_self_test_operation.value // 0) != 0
  else
    ((.ata_smart_data.self_test.status.value // 0) / 16 | floor) == 15
  end;

[ .[] | select(.serial_number and .power_on_time.hours)
  | . as $d
  | "device=\"\(.device.name | ltrimstr("/dev/"))\",model_name=\"\(.model_name | esc)\",serial_number=\"\(.serial_number | esc)\"" as $l
  | { l: $l,
      running: (if running then 1 else 0 end),
      last: [ "short", "long" ] | map(. as $t
              | first($d | tests[] | select(.type == $t and .state != "aborted"))
              | . + { l: "\($l),type=\"\($t)\"" }) } ]
| ( "# HELP smart_selftest_last_age_seconds Power-on time since the newest completed self-test of this type.",
    "# TYPE smart_selftest_last_age_seconds gauge",
    (.[].last[] | "smart_selftest_last_age_seconds{\(.l)} \(.age_hours * 3600)"),
    "# HELP smart_selftest_last_failed 1 if the newest completed self-test of this type failed.",
    "# TYPE smart_selftest_last_failed gauge",
    (.[].last[] | "smart_selftest_last_failed{\(.l)} \(if .state == "failed" then 1 else 0 end)"),
    "# HELP smart_selftest_running 1 while a self-test is in progress.",
    "# TYPE smart_selftest_running gauge",
    (.[] | "smart_selftest_running{\(.l)} \(.running)") )
