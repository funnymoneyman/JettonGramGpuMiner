#!/usr/bin/env bash

# Загрузка конфигураций
source /hive/miners/custom/mrdn-miner/h-manifest.conf

LOG_FILE="${CUSTOM_LOG_BASENAME}.log"
GPU_LOG="/hive/miners/custom/mrdn-miner/miner/miner_log.txt"

if [[ ! -f $LOG_FILE ]]; then
  echo -e "${RED}Log file ${YELLOW}$LOG_FILE${RED} is not found${NOCOLOR}"
  exit 1
fi

# Функция для расчета времени работы (uptime)
get_miner_uptime() {
  local start_time=$(stat --format='%Y' "$LOG_FILE")
  local current_time=$(date +%s)
  local uptime=$((current_time - start_time))
  
  echo $uptime
}

# Функция для извлечения хэшрейтов из лог-файла
get_hashrates() {
  local gpu_count=5  # Укажите количество GPU
  declare -A hash_rate_map
  local -a hs
  local -a ids

  hs=($(grep -oP "\[ done, passed: [0-9]+\.[0-9]+ms, hashes computed: [0-9]+, instant speed: \K[0-9]+\.[0-9]+" "$GPU_LOG" | tail -n ${gpu_count}))
  ids=($(grep -oP "\[ START MINER, GPU ID: \K[0-9]+" "$GPU_LOG" | tail -n ${gpu_count}))

  # Перевернуть массивы
  hs=($(echo "${hs[@]}" | tac -s ' '))
  ids=($(echo "${ids[@]}" | tac -s ' '))

  # Сопоставление хэшрейтов и GPU ID
  for (( i=0; i < ${gpu_count}; i++ )); do
    hash_rate_map[${ids[$i]}]=${hs[$i]}
  done

  # Формирование окончательного массива хэшрейтов
  for (( i=0; i < ${gpu_count}; i++ )); do
    hs[$i]=${hash_rate_map[$i]:-0}
  done

  echo "${hs[@]}"
}

# Функция для извлечения температур из nvtool
get_temperatures() {
  local temps=()
  while IFS= read -r line; do
    if [[ $line =~ TEMPERATURE:\ ([0-9]+) ]]; then
      temps+=("${BASH_REMATCH[1]}")
    fi
  done < <(nvtool -t)
  echo "${temps[@]}"
}

# Функция для извлечения скоростей вентиляторов из nvtool
get_fan_speeds() {
  local fans=()
  while IFS= read -r line; do
    if [[ $line =~ FAN\ SPEED:\ ([0-9]+) ]]; then
      fans+=("${BASH_REMATCH[1]}")
    fi
  done < <(nvtool -f)
  echo "${fans[@]}"
}

# Извлечение данных из логов
hashrates=($(get_hashrates))
accepted=$(grep "not mined" $LOG_FILE | tail -1 | awk '{print $(NF-2)}')
rejected=$(grep "not mined" $LOG_FILE | tail -1 | awk '{print $(NF-1)}')

# Получение температур и скоростей вентиляторов
temperatures=($(get_temperatures))
fan_speeds=($(get_fan_speeds))

# Расчет общего хэшрейта
total_hashrate=0
for hr in "${hashrates[@]}"; do
  total_hashrate=$(echo "$total_hashrate + $hr" | bc)
done

# Расчет времени работы (uptime)
uptime=$(get_miner_uptime)

# Формирование JSON-статистики
stats=$(jq -nc --argjson hs "$(printf '%s\n' "${hashrates[@]}" | jq -R . | jq -s .)" \
            --arg hs_units "Mhash/s" \
            --arg algo "TON" \
            --arg ver "" \
            --argjson ar "[$accepted, $rejected]" \
            --argjson temp "$(printf '%s\n' "${temperatures[@]}" | jq -R . | jq -s .)" \
            --argjson fan "$(printf '%s\n' "${fan_speeds[@]}" | jq -R . | jq -s .)" \
            --argjson power "[]" \
            --arg uptime "$uptime" \
            --arg total_hashrate "$total_hashrate" \
            '{hs: $hs, hs_units: $hs_units, algo: $algo, ver: $ver, ar: $ar, temp: $temp, fan: $fan, power: $power, uptime: $uptime, total_hashrate: $total_hashrate}')

# Вывод данных
echo "TOTAL HASHRATE: $total_hashrate Mhash/s"
echo "HASHRATES: ${hashrates[@]}"
echo "ACCEPTED: $accepted"
echo "REJECTED: $rejected"
echo "UPTIME: $uptime"
echo $stats
