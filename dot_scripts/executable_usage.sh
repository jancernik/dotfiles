#!/usr/bin/env bash

# Display Claude, Codex, and OpenCode Go usage.

set -euo pipefail

WARN=70
CRIT=90

GLYPH_FULL=$'\u2501'
GLYPH_HALF=$'\u2578'
GLYPH_EMPTY=$'\u2500'

HOME_DIR=$HOME
CSWAP_CACHE="$HOME_DIR/.local/share/claude-swap/cache/usage.json"
CSWAP_SEQ="$HOME_DIR/.local/share/claude-swap/sequence.json"
CLAUDE_CREDS="$HOME_DIR/.claude/.credentials.json"
CLAUDE_JSON="$HOME_DIR/.claude.json"
CODEX_AUTH="$HOME_DIR/.codex/auth.json"
PI_AUTH="$HOME_DIR/.pi/agent/auth.json"
OC_AUTH_A="$HOME_DIR/.local/share/opencode/auth.json"
OC_AUTH_B="$HOME_DIR/.config/opencode/auth.json"

if [[ -n ${NO_COLOR:-} ]]; then
  COLOR=0
elif [[ -n ${FORCE_COLOR:-} ]]; then
  COLOR=1
elif [[ -t 1 && ${TERM:-} != dumb ]]; then
  COLOR=1
else
  COLOR=0
fi

st() {
  if (( COLOR )); then
    printf '\033[%sm%s\033[0m' "$1" "$2"
  else
    printf '%s' "$2"
  fi
}

sev_code() {
  local p=${1%%.*}
  [[ $p =~ ^-?[0-9]+$ ]] || p=0
  if (( p >= CRIT )); then printf '38;5;167'
  elif (( p >= WARN )); then printf '38;5;179'
  else printf '38;5;108'; fi
}

bar() {
  local pct=$1 width=$2 out="" i full half color p_int
  if [[ -z $pct ]]; then
    for ((i = 0; i < width; i++)); do out+="$(st "38;5;238" "$GLYPH_EMPTY")"; done
    printf '%s' "$out"
    return
  fi
  p_int=${pct%%.*}
  [[ $p_int =~ ^-?[0-9]+$ ]] || p_int=0
  color=$(sev_code "$p_int")
  read -r full half <<<"$(awk -v p="$pct" -v w="$width" 'BEGIN{
    c = p / 100 * w; if (c < 0) c = 0; if (c > w) c = w;
    f = int(c); h = (c - f >= 0.5 && f < w) ? 1 : 0; print f, h }')"
  for ((i = 0; i < width; i++)); do
    if (( i < full )); then out+="$(st "$color" "$GLYPH_FULL")"
    elif (( i == full && half == 1 )); then out+="$(st "$color" "$GLYPH_HALF")"
    else out+="$(st "38;5;238" "$GLYPH_EMPTY")"; fi
  done
  printf '%s' "$out"
}

fmt_dur() {
  local s=${1%%.*}
  [[ $s =~ ^-?[0-9]+$ ]] || s=0
  if (( s < 0 )); then s=0; fi
  if (( s < 60 )); then printf '%ss' "$s"
  elif (( s < 3600 )); then printf '%sm' "$((s / 60))"
  elif (( s < 86400 )); then
    local h=$((s / 3600)) m=$(((s % 3600) / 60))
    if (( m )); then printf '%sh %sm' "$h" "$m"; else printf '%sh' "$h"; fi
  else
    local d=$((s / 86400)) h=$(((s % 86400) / 3600))
    if (( h )); then printf '%sd %sh' "$d" "$h"; else printf '%sd' "$d"; fi
  fi
}

iso_to_epoch() {
  [[ -n $1 ]] || return 0
  [[ $1 =~ ^[0-9]+(\.[0-9]+)?$ ]] && { printf '%.0f' "$1"; return; }
  [[ $1 =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})?$ ]] || return 0
  date -u -d "$1" +%s 2>/dev/null || true
}

pace_ahead() {
  awk -v p="$1" -v r="$2" -v f="$3" 'BEGIN{
    if (r == "" || f == "" || r == 0 || f == 0) print 0;
    else {
      rem = (r - f) % 604800; el = (rem == 0) ? 0 : 604800 - rem;
      if (el < 86400) print 0;
      else {
        expected = el / 6048.0; if (expected > 100) expected = 100;
        print (p - expected >= 15) ? 1 : 0
      }
    }}'
}

reset_suffix() {
  local ts=${1%%.*}
  [[ $ts =~ ^[0-9]+$ ]] || return 0
  local now remaining
  now=$(date +%s)
  remaining=$((ts - now))
  if (( remaining <= 0 )); then printf 'resets now'; return; fi
  if [[ $(date -d @"$ts" +%F) == "$(date +%F)" ]]; then
    printf 'resets %s \xc2\xb7 %s' "$(fmt_dur "$remaining")" "$(date -d @"$ts" +%H:%M)"
  else
    printf 'resets %s \xc2\xb7 %s' "$(fmt_dur "$remaining")" "$(date -d @"$ts" +'%b %-d %H:%M')"
  fi
}

SEP=$'\x1f'
OUT=""
emit_card() { printf 'CARD\x1f%s\x1f%s\x1f%s\x1f%s\n' "$1" "$2" "$3" "$4" >>"$OUT"; }
emit_err() { printf 'ERR\x1f%s\n' "$1" >>"$OUT"; }
emit_row() { printf 'ROW\x1f%s\x1f%s\x1f%s\x1f%s\n' "$1" "$2" "$3" "$4" >>"$OUT"; }

iso_now() { date -u +'%Y-%m-%dT%H:%M:%SZ'; }

money() {
  awk -v u="$1" -v l="$2" 'BEGIN{printf "$%.2f / $%.2f", u, l}'
}

emit_usage_cswap_schema() {
  local usage=$1 spend five seven
  spend=$(jq -c '.spend // empty' <<<"$usage")
  if [[ -n $spend ]]; then
    emit_row '$$' "$(jq -r '.pct' <<<"$spend")" \
      "$(iso_to_epoch "$(jq -r '.resetsAt // empty' <<<"$spend")")" \
      "$(money "$(jq -r '.used' <<<"$spend")" "$(jq -r '.limit' <<<"$spend")")"
  fi
  five=$(jq -c '.fiveHour // empty' <<<"$usage")
  [[ -n $five ]] && emit_row '5h' "$(jq -r '.pct' <<<"$five")" \
    "$(iso_to_epoch "$(jq -r '.resetsAt // empty' <<<"$five")")" ""
  seven=$(jq -c '.sevenDay // empty' <<<"$usage")
  if [[ -n $seven ]]; then
    local extra=""
    [[ $(jq -r '.aheadOfPace // false' <<<"$seven") == true ]] && extra="(ahead of pace)"
    emit_row '7d' "$(jq -r '.pct' <<<"$seven")" \
      "$(iso_to_epoch "$(jq -r '.resetsAt // empty' <<<"$seven")")" "$extra"
  fi
  local scoped
  scoped=$(jq -c '.scoped // [] | length' <<<"$usage")
  if (( scoped > 0 )); then
    while IFS="$SEP" read -r name pct resets ahead; do
      local extra=""
      if [[ $(awk -v p="$pct" 'BEGIN{print (p>=100)?1:0}') == 1 ]]; then extra="(!)"
      elif [[ $ahead == true ]]; then extra="(ahead of pace)"; fi
      emit_row "$name" "$pct" "$(iso_to_epoch "$resets")" "$extra"
    done < <(jq -r '.scoped // [] | .[] |
      [.name, (.pct | tostring), (.resetsAt // "-"), (.aheadOfPace // false)] |
      join("\u001f")' <<<"$usage")
  fi
}

claude_from_cswap() {
  local json=$1 norm=$2
  local total
  total=$(jq '.accounts | length' "$json")
  if (( total == 0 )); then
    emit_card "" "Claude" "" 0
    emit_err "cswap reported no accounts"
    printf '{"cards": []}' >"$norm"
    return
  fi
  printf '{"cards": %s}' "$(jq -c '[.accounts[] |
    {title: .email, tag: (.organizationName // "personal"), active: .active,
     number: (.number | tostring),
     error: (if .usageStatus and .usageStatus != "ok"
             then (.usageStatus | gsub("_"; " ")) else null end),
     windows: ([(.usage.spend // null | select(. != null) |
                 {label: "$$", pct: .pct, resetsAt: .resetsAt,
                  extra: "$\(.used) / $\(.limit)"} )] +
                [(.usage.fiveHour // null | select(. != null) |
                 {label: "5h", pct: .pct, resetsAt: .resetsAt, extra: null})] +
                [(.usage.sevenDay // null | select(. != null) |
                 {label: "7d", pct: .pct, resetsAt: .resetsAt,
                  extra: (if .aheadOfPace then "(ahead of pace)" else null end)})] +
                [(.usage.scoped // [])[] |
                 {label: .name, pct: .pct, resetsAt: .resetsAt,
                  extra: (if .aheadOfPace then "(ahead of pace)" else null end)}])}]' "$json")" >"$norm"
  local idx=0
  while (( idx < total )); do
    local acc status usage
    acc=$(jq -c ".accounts[$idx]" "$json")
    jq -r '[(if .active then 1 else 0 end), (.number | tostring), .email,
            (.organizationName // "personal")] | @tsv' <<<"$acc" |
      while IFS=$'\t' read -r active num email org; do
        emit_card "$num" "$email" "$org" "$active"
      done
    status=$(jq -r '.usageStatus // "ok"' <<<"$acc")
    usage=$(jq -c '.usage // empty' <<<"$acc")
    if [[ -z $usage ]]; then
      if [[ $status == ok ]]; then emit_err "usage unavailable"
      else emit_err "${status//_/ }"; fi
    else
      emit_usage_cswap_schema "$usage"
    fi
    ((idx += 1))
  done
}

claude_direct() {
  local norm=$1
  [[ -f $CLAUDE_CREDS ]] || return 1
  local tok
  tok=$(jq -r '.claudeAiOauth.accessToken // empty' "$CLAUDE_CREDS" 2>/dev/null) || return 1
  [[ -n $tok ]] || return 1

  local ver="2.1.278"
  if command -v claude >/dev/null 2>&1; then
    ver=$(claude --version 2>/dev/null | head -1 | awk '{print $1}')
    [[ $ver =~ ^[0-9]+\.[0-9]+ ]] || ver="2.1.278"
  fi

  local code
  code=$(curl -sS -o "$TMP/cl.json" -w '%{http_code}' --max-time 25 \
    -H "Authorization: Bearer $tok" \
    -H 'anthropic-beta: oauth-2025-04-20' \
    -H "User-Agent: claude-code/$ver" \
    -H 'Accept: application/json' \
    https://api.anthropic.com/api/oauth/usage 2>/dev/null) || code=000
  code=${code:-000}

  local email tag
  email=$(jq -r '.oauthAccount.emailAddress // empty' "$CLAUDE_JSON" 2>/dev/null || true)
  tag=$(jq -r '.claudeAiOauth.subscriptionType // "oauth"' "$CLAUDE_CREDS" 2>/dev/null || echo oauth)

  emit_card "" "${email:-claude}" "$tag" 1
  if [[ $code != 200 ]]; then
    case $code in
      429) emit_err "HTTP 429 rate limited (retry in a few minutes)" ;;
      401) emit_err "token expired (run claude once to refresh)" ;;
      000) emit_err "network error" ;;
      *) emit_err "HTTP $code" ;;
    esac
    printf '{"cards": []}' >"$norm"
    return 0
  fi
  if ! jq -e '
      type == "object" and
      (has("five_hour") or has("seven_day")) and
      all([.five_hour, .seven_day, .extra_usage][]; . == null or type == "object") and
      (.limits == null or (.limits | type == "array" and all(.[]; type == "object")))' \
      "$TMP/cl.json" >/dev/null 2>&1; then
    emit_err "invalid usage response"
    printf '{"cards": []}' >"$norm"
    return 0
  fi

  local now t5 t7 pct7
  now=$(date +%s)
  local raw
  raw=$(cat "$TMP/cl.json")
  local eu
  eu=$(jq -c '.extra_usage // empty' <<<"$raw")
  if [[ -n $eu ]] && jq -e '.is_enabled == true and
      all([.utilization, .used_credits, .monthly_limit][]; type == "number")' \
      <<<"$eu" >/dev/null; then
    emit_row '$$' "$(jq -r '.utilization' <<<"$eu")" \
      "$(iso_to_epoch "$(jq -r '.resets_at // empty' <<<"$eu")")" \
      "$(money "$(awk -v c="$(jq -r '.used_credits' <<<"$eu")" 'BEGIN{print c/100}')" \
           "$(awk -v c="$(jq -r '.monthly_limit' <<<"$eu")" 'BEGIN{print c/100}')")"
  fi
  t5=$(iso_to_epoch "$(jq -r '.five_hour.resets_at // ""' <<<"$raw")")
  emit_row '5h' "$(jq -r '.five_hour.utilization' <<<"$raw")" "$t5" ""
  pct7=$(jq -r '.seven_day.utilization' <<<"$raw")
  t7=$(iso_to_epoch "$(jq -r '.seven_day.resets_at // ""' <<<"$raw")")
  local extra7=""
  [[ $(pace_ahead "$pct7" "$t7" "$now") == 1 ]] && extra7="(ahead of pace)"
  emit_row '7d' "$pct7" "$t7" "${extra7:-}"
  while IFS="$SEP" read -r name pct resets; do
    [[ -n $name ]] || continue
    local extra=""
    [[ $(awk -v p="$pct" 'BEGIN{print (p>=100)?1:0}') == 1 ]] && extra="(!)"
    emit_row "$name" "$pct" "$(iso_to_epoch "$resets")" "$extra"
  done < <(jq -r '.limits // [] | .[] |
      select((.scope.model.display_name // "") != "") |
      [.scope.model.display_name, (.percent | tostring), (.resets_at // "-")] |
      join("\u001f")' <<<"$raw")

  claude_norm_from_raw "$TMP/cl.json" "$email" "$tag" >"$norm"
  return 0
}

claude_norm_from_raw() {
  jq --arg email "${2:-claude}" --arg tag "$3" '
    {cards: [{
      title: $email, tag: $tag, active: true, number: null, error: null,
      windows: ([
        (if .extra_usage.is_enabled == true and
             all([.extra_usage.utilization, .extra_usage.used_credits,
                  .extra_usage.monthly_limit][]; type == "number") then
          {label: "$$", pct: .extra_usage.utilization,
           resetsAt: .extra_usage.resets_at, extra: null}
         else empty end),
        {label: "5h", pct: .five_hour.utilization, resetsAt: .five_hour.resets_at, extra: null},
        {label: "7d", pct: .seven_day.utilization, resetsAt: .seven_day.resets_at, extra: null}
      ] + [(.limits // [])[] | select((.scope.model.display_name // "") != "") |
           {label: .scope.model.display_name, pct: .percent, resetsAt: .resets_at,
            extra: (if .percent >= 100 then "(!)" else null end)}])
    }]}' "$1"
}

claude_from_cache() {
  local norm=$1
  local active
  active=$(jq -r '.activeAccountNumber // 0' "$CSWAP_SEQ" 2>/dev/null || echo 0)
  printf '{"cards": [' >"$norm"
  local first=1
  while IFS=$'\t' read -r num email; do
    emit_card "$num" "$email" "personal" "$([[ $num == "$active" ]] && echo 1 || echo 0)"
    local last
    last=$(jq -c --arg n "$num" '.accounts[$n].lastGood // empty' "$CSWAP_CACHE" 2>/dev/null || true)
    local rows="[]"
    if [[ -n $last ]]; then
      rows=$(jq -c '[
        (if .spend then {label: "$$", pct: .spend.pct, resetsAt: null,
          extra: null} else empty end),
        (if .five_hour then {label: "5h", pct: .five_hour.pct, resetsAt: null,
          extra: null} else empty end),
        (if .seven_day then {label: "7d", pct: .seven_day.pct,
          resetsAt: .seven_day.resets_at, extra: null} else empty end)
      ]' <<<"$last")
      local spend five seven
      spend=$(jq -c '.spend // empty' <<<"$last")
      [[ -n $spend ]] && emit_row '$$' "$(jq -r '.pct' <<<"$spend")" "" \
        "$(money "$(jq -r '.used' <<<"$spend")" "$(jq -r '.limit' <<<"$spend")")"
      five=$(jq -c '.five_hour // empty' <<<"$last")
      [[ -n $five ]] && emit_row '5h' "$(jq -r '.pct' <<<"$five")" "" ""
      seven=$(jq -c '.seven_day // empty' <<<"$last")
      [[ -n $seven ]] && emit_row '7d' "$(jq -r '.pct' <<<"$seven")" \
        "$(iso_to_epoch "$(jq -r '.resets_at // ""' <<<"$seven")")" ""
    fi
    (( first )) || printf ',' >>"$norm"
    first=0
    jq -cn --arg n "$num" --arg e "$email" \
      --argjson a "$([[ $num == "$active" ]] && echo true || echo false)" \
      --argjson w "$rows" \
      '{title: $e, tag: "personal", active: $a, number: $n, error: null, windows: $w}' >>"$norm"
  done < <(jq -r '.accounts | to_entries[] | [.key, (.value.email // "")] | @tsv' \
      "$CSWAP_CACHE" 2>/dev/null)
  printf ']}' >>"$norm"
}

fetch_claude() {
  OUT=$1
  : >"$OUT"
  local norm=$2

  local cswap_error=""
  if [[ -n ${CSWAP_BIN:-} ]]; then
    if timeout 45 "$CSWAP_BIN" list --json >"$TMP/cswap.json" 2>/dev/null; then
      if jq -se '
          def object_or_null: . == null or type == "object";
          def scoped_or_null: . == null or (type == "array" and all(.[]; type == "object"));
          length == 1 and (.[0] | type == "object" and
            (.accounts | type == "array") and
            all(.accounts[]; type == "object" and
              (.email | type == "string") and
              (.number | type == "number" or type == "string") and
              (.usage | object_or_null) and
              (.usage.spend | object_or_null) and
              (.usage.fiveHour | object_or_null) and
              (.usage.sevenDay | object_or_null) and
              (.usage.scoped | scoped_or_null)))' \
          "$TMP/cswap.json" >/dev/null 2>&1; then
        claude_from_cswap "$TMP/cswap.json" "$norm"
        return
      fi
      cswap_error="cswap output is not valid usage JSON"
    else
      cswap_error="cswap unavailable and no Claude credentials"
    fi
  fi
  if claude_direct "$norm"; then return; fi
  if [[ -f $CSWAP_CACHE ]]; then
    if jq -e 'type == "object" and (.accounts | type == "object") and
        all(.accounts[]; type == "object")' "$CSWAP_CACHE" >/dev/null 2>&1; then
      claude_from_cache "$norm"
      return
    fi
    cswap_error="Claude usage cache is invalid"
  fi
  emit_card "" "Claude" "" 0
  emit_err "${cswap_error:-cswap not found and no Claude credentials}"
  printf '{"cards": []}' >"$norm"
}

fetch_codex() {
  OUT=$1
  : >"$OUT"
  local norm=$2
  if [[ ! -f $CODEX_AUTH ]]; then
    emit_card "" "Codex" "" 0
    emit_err "not logged in (~/.codex/auth.json missing)"
    printf '{"cards": []}' >"$norm"
    return
  fi
  local tok acct
  tok=$(jq -r '.tokens.access_token // empty' "$CODEX_AUTH" 2>/dev/null || true)
  acct=$(jq -r '.tokens.account_id // empty' "$CODEX_AUTH" 2>/dev/null || true)
  if [[ -z $tok ]]; then
    emit_card "" "Codex" "" 0
    emit_err "not logged in (no access token)"
    printf '{"cards": []}' >"$norm"
    return
  fi
  local code
  code=$(curl -sS -o "$TMP/codex.json" -w '%{http_code}' --max-time 25 \
    -H "Authorization: Bearer $tok" \
    ${acct:+-H "ChatGPT-Account-Id: $acct"} \
    -H 'Accept: application/json' \
    -H 'User-Agent: Mozilla/5.0' \
    https://chatgpt.com/backend-api/wham/usage 2>/dev/null) || code=000
  if [[ $code != 200 ]]; then
    emit_card "" "Codex" "" 0
    emit_err "HTTP $code"
    printf '{"cards": []}' >"$norm"
    return
  fi
  if ! jq -e '
      type == "object" and
      (has("rate_limit") or has("code_review_rate_limit")) and
      all([.rate_limit, .rate_limit.primary_window, .rate_limit.secondary_window,
           .code_review_rate_limit, .rate_limit_reset_credits][];
          . == null or type == "object")' \
      "$TMP/codex.json" >/dev/null 2>&1; then
    emit_card "" "Codex" "" 0
    emit_err "invalid usage response"
    printf '{"cards": []}' >"$norm"
    return
  fi
  local email plan plan_tag credits now
  email=$(jq -r '.email // empty' "$TMP/codex.json")
  plan=$(jq -r '.plan_type // "chatgpt"' "$TMP/codex.json")
  plan_tag="${plan^}"
  credits=$(jq -r '.rate_limit_reset_credits.available_count // 0' "$TMP/codex.json")
  (( credits > 0 )) && plan_tag="$plan_tag · $credits reset credits"
  emit_card "" "${email:-Codex}" "$plan_tag" 0
  now=$(date +%s)
  local win pct ts
  win=$(jq -c '.rate_limit.primary_window // empty' "$TMP/codex.json")
  [[ -n $win ]] && emit_row '5h' "$(jq -r '.used_percent' <<<"$win")" \
    "$(jq -r '.reset_at' <<<"$win")" ""
  win=$(jq -c '.rate_limit.secondary_window // empty' "$TMP/codex.json")
  if [[ -n $win ]]; then
    pct=$(jq -r '.used_percent' <<<"$win")
    ts=$(jq -r '.reset_at' <<<"$win")
    local extra=""
    [[ $(pace_ahead "$pct" "$ts" "$now") == 1 ]] && extra="(ahead of pace)"
    emit_row '7d' "$pct" "$ts" "$extra"
  fi
  win=$(jq -c '.code_review_rate_limit // empty' "$TMP/codex.json")
  [[ -n $win ]] && emit_row 'review' "$(jq -r '.used_percent' <<<"$win")" \
    "$(jq -r '.reset_at' <<<"$win")" ""

  jq --arg e "${email:-Codex}" --arg t "$plan_tag" '
    def w(l; p; r; x):
      {label: l, pct: p,
       resetsAt: (if r then (r | todateiso8601) else null end),
       extra: (if x == "" then null else x end)};
    {cards: [{
      title: $e, tag: $t, active: false, number: null, error: null,
      windows: ([
        (if .rate_limit.primary_window then
          w("5h"; .rate_limit.primary_window.used_percent;
            .rate_limit.primary_window.reset_at; "") else empty end),
        (if .rate_limit.secondary_window then
          w("7d"; .rate_limit.secondary_window.used_percent;
            .rate_limit.secondary_window.reset_at; "") else empty end),
        (if .code_review_rate_limit then
          w("review"; .code_review_rate_limit.used_percent;
            .code_review_rate_limit.reset_at; "") else empty end)
      ])}]}' "$TMP/codex.json" >"$norm"
}

go_key() {
  local f k
  for f in "$PI_AUTH" "$OC_AUTH_A" "$OC_AUTH_B"; do
    [[ -f $f ]] || continue
    k=$(jq -r '."opencode-go".key // empty' "$f" 2>/dev/null || true)
    [[ -n $k ]] && { printf '%s' "$k"; return; }
  done
  printf '%s' "${OPENCODE_GO_API_KEY:-}"
}

fetch_go() {
  OUT=$1
  : >"$OUT"
  local norm=$2
  local key
  key=$(go_key)
  if [[ -z $key ]]; then
    emit_card "" "OpenCode Go" "" 0
    emit_err "no API key (pi/opencode auth.json)"
    printf '{"cards": []}' >"$norm"
    return
  fi
  local code
  code=$(curl -sS -o "$TMP/go.json" -w '%{http_code}' --max-time 25 \
    -H "Authorization: Bearer $key" \
    -H 'Accept: application/json' \
    -H 'User-Agent: pi-coding-agent/usage' \
    https://opencode.ai/zen/go/v1/usage 2>/dev/null) || code=000
  if [[ $code != 200 ]]; then
    emit_card "" "OpenCode Go" "" 0
    emit_err "HTTP $code"
    printf '{"cards": []}' >"$norm"
    return
  fi
  if ! jq -e '
      type == "object" and (.usage | type == "object") and
      all([.usage.rolling, .usage.weekly, .usage.monthly][];
          . == null or type == "object")' \
      "$TMP/go.json" >/dev/null 2>&1; then
    emit_card "" "OpenCode Go" "" 0
    emit_err "invalid usage response"
    printf '{"cards": []}' >"$norm"
    return
  fi
  emit_card "" "Go" '$10/mo' 0
  local now tep
  now=$(date +%s)
  local key_name label weekly win pct ts status extra
  while IFS='|' read -r key_name label weekly; do
    win=$(jq -c --arg k "$key_name" '.usage[$k] // empty' "$TMP/go.json")
    [[ -n $win ]] || continue
    pct=$(jq -r '.percent' <<<"$win")
    ts=$(jq -r '.resetsAt // ""' <<<"$win")
    status=$(jq -r '.status // "ok"' <<<"$win")
    extra=""
    if [[ $status != ok ]]; then extra="$status"
    elif [[ $weekly == 1 ]]; then
      tep=$(iso_to_epoch "$ts")
      [[ $(pace_ahead "$pct" "$tep" "$now") == 1 ]] && extra="(ahead of pace)"
    fi
    emit_row "$label" "$pct" "$(iso_to_epoch "$ts")" "$extra"
  done <<EOF
rolling|5h|0
weekly|7d|1
monthly|30d|0
EOF
  go_norm "$TMP/go.json" >"$norm"
}

go_norm() {
  jq '{cards: [{
      title: "Go", tag: "$10/mo", active: false, number: null, error: null,
      windows: ([
        (if .usage.rolling then
          {label: "5h", pct: .usage.rolling.percent, resetsAt: .usage.rolling.resetsAt,
           extra: (if .usage.rolling.status != "ok" then .usage.rolling.status else null end)}
         else empty end),
        (if .usage.weekly then
          {label: "7d", pct: .usage.weekly.percent, resetsAt: .usage.weekly.resetsAt,
           extra: (if .usage.weekly.status != "ok" then .usage.weekly.status else null end)}
         else empty end),
        (if .usage.monthly then
          {label: "30d", pct: .usage.monthly.percent, resetsAt: .usage.monthly.resetsAt,
           extra: (if .usage.monthly.status != "ok" then .usage.monthly.status else null end)}
         else empty end)
      ])}]}' "$1"
}

render_tsv() {
  local f=$1 bar_w=$2
  local kind f1 f2 f3 f4
  local label_w=0
  while IFS="$SEP" read -r kind f1 f2 f3 f4; do
    if [[ $kind == ROW && ${#f1} -gt $label_w ]]; then label_w=${#f1}; fi
  done <"$f"
  local first_card=1
  while IFS="$SEP" read -r kind f1 f2 f3 f4; do
    case $kind in
      CARD)
        (( first_card )) || BUF+=$'\n'
        first_card=0
        local head=""
        head+="$(st "38;5;252" "$f2")"
        [[ -n $f3 ]] && head+="  $(st "38;5;245" "[$f3]")"
        [[ $f4 == 1 ]] && head+="   $(st "1;38;5;173" "● active")"
        BUF+="$head"$'\n'
        ;;
      ERR) BUF+="    $(st "38;5;245" "· $f1")"$'\n' ;;
      ROW)
        local pad pct_txt p_int suffix=""
        printf -v pad '%-*s' "$label_w" "$f1"
        if [[ $f2 == null ]]; then f2=""; fi
        if [[ -z $f2 ]]; then
          pct_txt="   "
        else
          pct_txt=$(awk -v p="$f2" 'BEGIN{printf "%3.0f%%", p}')
        fi
        p_int=${f2%%.*}; [[ $p_int =~ ^-?[0-9]+$ ]] || p_int=0
        [[ -n $f3 ]] && suffix=$(reset_suffix "$f3")
        [[ -n $f4 ]] && suffix="${suffix:+$suffix  }$f4"
        BUF+="    $(st "38;5;245" "$pad") $(bar "$f2" "$bar_w") $(st "$(sev_code "$p_int")" "$pct_txt")"
        [[ -n $suffix ]] && BUF+="  $(st "38;5;245" "$suffix")"
        BUF+=$'\n'
        ;;
    esac
  done <"$f"
  (( first_card )) || BUF+=$'\n'
}

emit_json() {
  jq -n \
    --slurpfile c "$1" --slurpfile x "$2" --slurpfile g "$3" \
    --arg now "$4" '{
      checkedAt: $now,
      claude: ($c[0].cards // []),
      codex: ($x[0].cards[0] // null),
      opencodeGo: ($g[0].cards[0] // null)
    }'
}

fetch_failed() {
  OUT=$1
  : >"$OUT"
  emit_card "" "$3" "" 0
  emit_err "usage fetch failed"
  printf '{"cards": []}' >"$2"
}

main() {
  local json_mode=0 provider=all a
  for a in "$@"; do
    case $a in
      --json) json_mode=1 ;;
      all) provider=all ;;
      claude|codex|go|opencode|opencode-go) provider=$a ;;
      -h|--help)
        printf '%s\n' \
          'usage.sh — Claude (via cswap, or direct OAuth fallback), Codex, and OpenCode Go' \
          'usage rendered as cswap-style bars.' \
          '' \
          'Requires: bash 4+, curl, jq, GNU date.' \
          'Usage: usage.sh [--json] [all|claude|codex|go]'
        return 0 ;;
      *) printf 'usage: usage.sh [--json] [all|claude|codex|go]\n' >&2; return 2 ;;
    esac
  done
  [[ $provider == opencode || $provider == "opencode-go" ]] && provider=go

  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT

  CSWAP_BIN=${CSWAP_BIN:-$(command -v cswap || true)}

  local P1="" P2="" P3=""
  if [[ $provider == all || $provider == claude ]]; then
    fetch_claude "$TMP/claude.tsv" "$TMP/claude.norm" & P1=$!
  fi
  if [[ $provider == all || $provider == codex ]]; then
    fetch_codex "$TMP/codex.tsv" "$TMP/codex.norm" & P2=$!
  fi
  if [[ $provider == all || $provider == go ]]; then
    fetch_go "$TMP/go.tsv" "$TMP/go.norm" & P3=$!
  fi
  [[ -n $P1 ]] && { wait "$P1" || fetch_failed "$TMP/claude.tsv" "$TMP/claude.norm" "Claude"; }
  [[ -n $P2 ]] && { wait "$P2" || fetch_failed "$TMP/codex.tsv" "$TMP/codex.norm" "Codex"; }
  [[ -n $P3 ]] && { wait "$P3" || fetch_failed "$TMP/go.tsv" "$TMP/go.norm" "OpenCode Go"; }

  local now
  now=$(iso_now)
  if (( json_mode )); then
    case $provider in
      claude) jq -n --slurpfile c "$TMP/claude.norm" --arg now "$now" \
                '{checkedAt: $now, claude: ($c[0].cards // [])}' ;;
      codex)  jq -n --slurpfile x "$TMP/codex.norm" --arg now "$now" \
                '{checkedAt: $now, codex: ($x[0].cards[0] // null)}' ;;
      go)     jq -n --slurpfile g "$TMP/go.norm" --arg now "$now" \
                '{checkedAt: $now, opencodeGo: ($g[0].cards[0] // null)}' ;;
      all)    emit_json "$TMP/claude.norm" "$TMP/codex.norm" "$TMP/go.norm" "$now" ;;
    esac
    return
  fi

  local cols bw
  if [[ -n ${COLUMNS:-} ]]; then cols=$COLUMNS; else
    cols=$(tput cols 2>/dev/null || echo 100)
  fi
  bw=$((cols - 48))
  (( bw < 12 )) && bw=12
  (( bw > 28 )) && bw=28

  BUF=""
  if [[ $provider == all || $provider == claude ]]; then
    BUF+="$(st 2 Claude)"$'\n'
    render_tsv "$TMP/claude.tsv" "$bw"
  fi
  if [[ $provider == all || $provider == codex ]]; then
    BUF+="$(st 2 Codex)"$'\n'
    render_tsv "$TMP/codex.tsv" "$bw"
  fi
  if [[ $provider == all || $provider == go ]]; then
    BUF+="$(st 2 "OpenCode Go")"$'\n'
    render_tsv "$TMP/go.tsv" "$bw"
  fi
  printf '%s' "$BUF"
}

main "$@"
