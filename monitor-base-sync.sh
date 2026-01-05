#!/bin/bash

SERVICE="execution"

draw_progress_bar() {
  local percent=$1
  local width=50
  local filled=$(( width * percent / 100 ))
  local empty=$(( width - filled ))
  printf "["
  printf "%${filled}s" | tr ' ' '█'
  printf "%${empty}s" | tr ' ' '░'
  printf "] %3d%%\n" "$percent"
}

echo "Base Sync Monitor – Progress + ETA + Speed (updates every 20s – Ctrl+C to stop)"
echo ""

while true; do
  LOGS=$(docker compose logs --tail=20000 $SERVICE 2>/dev/null)

  # Highest synced block from Imported lines
  SYNCED_BLOCK=$(echo "$LOGS" | grep "Imported new chain segment" | \
    sed -E 's/.*number=([0-9,]+).*/\1/' | tr -d ',' | sort -nr | head -1)

  # Highest network head from Forkchoice lines
  NETWORK_HEAD=$(echo "$LOGS" | grep "Forkchoice requested sync to new head" | \
    sed -E 's/.*number=([0-9,]+).*/\1/' | tr -d ',' | sort -nr | head -1)

  if [[ -z "$SYNCED_BLOCK" || -z "$NETWORK_HEAD" ]]; then
    clear
    echo "($(date '+%H:%M:%S')) Waiting for import/forkchoice logs..."
    sleep 20
    continue
  fi

  BLOCKS_BEHIND=$((NETWORK_HEAD - SYNCED_BLOCK))
  if [[ $BLOCKS_BEHIND -lt 0 ]]; then BLOCKS_BEHIND=0; fi

  PERCENT=$(awk "BEGIN {printf \"%d\", (100 * $SYNCED_BLOCK / $NETWORK_HEAD) + 0.5}")
  if [[ $PERCENT -gt 100 ]]; then PERCENT=100; fi

  PROGRESS_BAR=$(draw_progress_bar $PERCENT)

  # Speed from last 30 imports using elapsed
  AVG_BLOCKS_PER_SEC=$(echo "$LOGS" | grep "Imported new chain segment" | tail -30 | \
    awk '
      {
        if (match($0, /blocks=([0-9]+)/, b)) blocks += b[1]
        if (match($0, /elapsed=([0-9.]+)s/, e)) elapsed += e[1]
      } END {
        if (elapsed > 0) printf "%.1f", blocks / elapsed
        else print "0"
      }
    ')

  clear
  echo "($(date '+%H:%M:%S')) Base Sync"
  echo -n "$PROGRESS_BAR"

  # Safe floating point comparison using awk
  if awk "BEGIN {exit !($AVG_BLOCKS_PER_SEC > 10)}"; then
    BLOCKS_PER_HOUR=$(awk "BEGIN {printf \"%d\", $AVG_BLOCKS_PER_SEC * 3600}")

    ETA_SEC=$(awk "BEGIN {printf \"%d\", $BLOCKS_BEHIND / $AVG_BLOCKS_PER_SEC + 60}")
    ETA_H=$(awk "BEGIN {printf \"%d\", $ETA_SEC / 3600}")
    ETA_M=$(awk "BEGIN {printf \"%d\", ($ETA_SEC % 3600) / 60}")
    ETA_S=$(awk "BEGIN {printf \"%d\", $ETA_SEC % 60}")

    echo "Estimated time remaining : ${ETA_H}h ${ETA_M}m ${ETA_S}s"
    echo "Current speed            : ~$BLOCKS_PER_HOUR blocks/hour"
  else
    echo "Sync complete or final stage – imports slowed"
  fi

  sleep 20
done
