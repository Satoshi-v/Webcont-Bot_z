#!/bin/bash
# ============================
# ZIVPN Instalador Completo Todo-en-Uno
# Manager + API + Bot de Telegram
# Listo para ejecutar vía SFTP
# Autor: Harun & GPT-5
# Traducción: Español
# ============================

# ============================
# 1️⃣ Verificar dependencias
# ============================
echo "Verificando dependencias..."
deps=(jq curl vnstat socat openssl)
for cmd in "${deps[@]}"; do
  if ! command -v $cmd >/dev/null 2>&1; then
    echo "Instalando $cmd..."
    apt update && apt install -y $cmd
  fi
done

# ============================
# 2️⃣ Crear carpetas y archivos
# ============================
mkdir -p /etc/zivpn
CONFIG_FILE="/etc/zivpn/config.json"
META_FILE="/etc/zivpn/accounts_meta.json"

[ ! -f "$CONFIG_FILE" ] && echo '{"auth":{"config":[]}, "listen":":5667"}' > "$CONFIG_FILE"
[ ! -f "$META_FILE" ] && echo '{"accounts":[]}' > "$META_FILE"

# ============================
# 2️⃣.1 Configurar ENV (BOT & API)
# ============================
ENV_FILE="/etc/zivpn/bot.env"

if [ ! -f "$ENV_FILE" ]; then
cat <<'EOF' > "$ENV_FILE"
# ============================
# CONFIGURACIÓN ZIVPN ENV
# ============================

# Telegram
BOT_TOKEN=TOKEN_DEL_BOT_AQUI
ADMIN_ID=ID_DEL_ADMIN_AQUI

# API
API_KEY=$(openssl rand -hex 16)
EOF

chmod 600 "$ENV_FILE"
fi


# ============================
# 3️⃣ Script del Manager
# ============================
MANAGER_SCRIPT="/usr/local/bin/zivpn-manager.sh"
SHORTCUT="/usr/local/bin/zivpn-manager"

rm -f "$MANAGER_SCRIPT" "$SHORTCUT"

cat <<'EOF' > "$MANAGER_SCRIPT"
#!/bin/bash
CONFIG_FILE="/etc/zivpn/config.json"
META_FILE="/etc/zivpn/accounts_meta.json"
SERVICE_NAME="zivpn.service"

[ ! -f "$META_FILE" ] && echo '{"accounts":[]}' > "$META_FILE"

sincronizar_cuentas() {
    for pass in $(jq -r ".auth.config[]" "$CONFIG_FILE"); do
        existe=$(jq -r --arg u "$pass" ".accounts[]?.user // empty | select(.==\$u)" "$META_FILE")
        [ -z "$existe" ] && jq --arg user "$pass" --arg exp "2099-12-31" \
            ".accounts += [{\"user\":\$user,\"expired\":\$exp}]" "$META_FILE" > /tmp/meta.tmp && mv /tmp/meta.tmp "$META_FILE"
    done
}

eliminar_expirados_auto() {
    hoy=$(date +%s)
    jq -c ".accounts[]" "$META_FILE" | while read -r acc; do
        user=$(echo "$acc" | jq -r ".user")
        exp=$(echo "$acc" | jq -r ".expired")
        exp_epoch=$(date -d "$exp" +%s 2>/dev/null)

        if [ "$hoy" -ge "$exp_epoch" ]; then
            jq --arg user "$user" '.auth.config |= map(select(. != $user))' "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"
            jq --arg user "$user" '.accounts |= map(select(.user != $user))' "$META_FILE" > /tmp/meta.tmp && mv /tmp/meta.tmp "$META_FILE"
            systemctl restart "$SERVICE_NAME" >/dev/null 2>&1
            echo "Auto eliminado expirado: $user"
        fi
    done
}

respaldar_cuentas() {
    BACKUP_DIR="/etc/zivpn"
    cp "$CONFIG_FILE" "$BACKUP_DIR/backup_config.json"
    cp "$META_FILE" "$BACKUP_DIR/backup_meta.json"
    echo "Respaldo completado (local)."
    read -rp "Enter para continuar..." enter
    menu
}

restaurar_cuentas() {
    BACKUP_DIR="/etc/zivpn"
    if [ ! -f "$BACKUP_DIR/backup_config.json" ] || [ ! -f "$BACKUP_DIR/backup_meta.json" ]; then
        echo "¡Respaldo no existe!"
        read -rp "Enter para continuar..." enter
        menu
    fi
    cp "$BACKUP_DIR/backup_config.json" "$CONFIG_FILE"
    cp "$BACKUP_DIR/backup_meta.json" "$META_FILE"
    systemctl restart "$SERVICE_NAME"
    echo "Restauración completada."
    read -rp "Enter para continuar..." enter
    menu
}

editar_bot_env() {
    ENV_FILE="/etc/zivpn/bot.env"

    if [ ! -f "$ENV_FILE" ]; then
        echo "❌ Archivo bot.env no encontrado!"
        read -rp "Enter para continuar..." enter
        menu
    fi

    source "$ENV_FILE"

    clear
    echo "===================================="
    echo "   CONFIGURACIÓN BOT & API ZIVPN"
    echo "===================================="
    echo "1) Cambiar TOKEN DEL BOT"
    echo "2) Cambiar ID DEL ADMIN"
    echo "3) Generar nueva CLAVE API"
    echo "0) Volver"
    echo "===================================="
    read -rp "Elige: " opt

    case "$opt" in
        1)
            read -rp "Nuevo TOKEN DEL BOT: " NEW_TOKEN
            [ -z "$NEW_TOKEN" ] && editar_bot_env
            sed -i "s|^BOT_TOKEN=.*|BOT_TOKEN=$NEW_TOKEN|" "$ENV_FILE"
            echo "✅ TOKEN DEL BOT cambiado correctamente"
        ;;
        2)
            read -rp "Nuevo ID DEL ADMIN: " NEW_ADMIN
            [ -z "$NEW_ADMIN" ] && editar_bot_env
            sed -i "s|^ADMIN_ID=.*|ADMIN_ID=$NEW_ADMIN|" "$ENV_FILE"
            echo "✅ ID DEL ADMIN cambiado correctamente"
        ;;
        3)
            NEW_KEY=$(openssl rand -hex 16)
            sed -i "s|^API_KEY=.*|API_KEY=$NEW_KEY|" "$ENV_FILE"
            echo "✅ Nueva CLAVE API creada correctamente:"
            echo "$NEW_KEY"
        ;;
        0)
            menu
        ;;
        *)
            editar_bot_env
        ;;
    esac

    echo ""
    echo "🔄 Reiniciando servicio..."
    systemctl restart zivpn-api.service
    systemctl restart zivpn-bot.service

    read -rp "Enter para continuar..." enter
    menu
}

menu() {
    clear
    sincronizar_cuentas

    echo "===================================="
    echo "     ADMINISTRADOR DE CUENTAS ZIVPN UDP"
    echo "===================================="

    VPS_IP=$(curl -s ifconfig.me || echo "No encontrado")
    echo "IP VPS       : ${VPS_IP}"

    ISP_NAME=$(curl -s https://ipinfo.io/org | sed 's/^[^ ]* //')
    echo "ISP          : ${ISP_NAME}"

    NET_IFACE=$(ip route | awk '/default/ {print $5}' | head -n1)

    BW_DIARIO_BAJADA=$(vnstat -i "$NET_IFACE" --json | jq -r '.interfaces[0].traffic.day[-1].rx')
    BW_DIARIO_SUBIDA=$(vnstat -i "$NET_IFACE" --json | jq -r '.interfaces[0].traffic.day[-1].tx')

    BW_MENSUAL_BAJADA=$(vnstat -i "$NET_IFACE" --json | jq -r '.interfaces[0].traffic.month[-1].rx')
    BW_MENSUAL_SUBIDA=$(vnstat -i "$NET_IFACE" --json | jq -r '.interfaces[0].traffic.month[-1].tx')

# Convertir de bytes a MB
    BW_DIARIO_BAJADA=$(awk -v b=$BW_DIARIO_BAJADA 'BEGIN {printf "%.2f MB", b/1024/1024}')
    BW_DIARIO_SUBIDA=$(awk -v b=$BW_DIARIO_SUBIDA 'BEGIN {printf "%.2f MB", b/1024/1024}')
    BW_MENSUAL_BAJADA=$(awk -v b=$BW_MENSUAL_BAJADA 'BEGIN {printf "%.2f MB", b/1024/1024}')
    BW_MENSUAL_SUBIDA=$(awk -v b=$BW_MENSUAL_SUBIDA 'BEGIN {printf "%.2f MB", b/1024/1024}')

    echo "Diario      : B $BW_DIARIO_BAJADA | S $BW_DIARIO_SUBIDA"
    echo "Mensual     : B $BW_MENSUAL_BAJADA | S $BW_MENSUAL_SUBIDA"
    echo "===================================="

    echo "1) Ver cuentas UDP"
    echo "2) Agregar nueva cuenta"
    echo "3) Eliminar cuenta"
    echo "4) Extender cuenta"
    echo "5) Reiniciar servicio"
    echo "6) Estado del VPS"
    echo "7) Respaldar"
    echo "8) Restaurar cuentas"
    echo "9) Configurar Bot & API"
    echo "0) Salir"
    echo "===================================="
    read -rp "Elige: " choice

    case $choice in
    1) listar_cuentas ;;
    2) agregar_cuenta ;;
    3) eliminar_cuenta ;;
    4) extender_cuenta ;;
    5) reiniciar_servicio ;;
    6) estado_vps ;;
    7) respaldar_cuentas ;;
    8) restaurar_cuentas ;;
    9) editar_bot_env ;;
    0) exit 0 ;;
    *) menu ;;
esac
}

listar_cuentas() {
    hoy=$(date +%s)
    jq -c ".accounts[]" "$META_FILE" | while read -r acc; do
        user=$(echo "$acc" | jq -r ".user")
        exp=$(echo "$acc" | jq -r ".expired")
        exp_ts=$(date -d "$exp" +%s 2>/dev/null)
        estado="Activo"
        [ "$hoy" -ge "$exp_ts" ] && estado="Expirado"
        echo "• $user | Exp: $exp | $estado"
    done
    read -rp "Enter para continuar..." enter
    menu
}

agregar_cuenta() {
    read -rp "Nueva contraseña: " new_pass
    [ -z "$new_pass" ] && menu

    # Verificar si la cuenta ya existe
    existe=$(jq -r --arg u "$new_pass" '.auth.config[] | select(.==$u)' "$CONFIG_FILE")
    if [ -n "$existe" ]; then
        echo "❌ La cuenta $new_pass ya existe!"
        read -rp "Presiona ENTER para volver al menú..." enter
        menu
    fi

    read -rp "Duración (días): " days
    [[ -z "$days" ]] && days=3

    exp_date=$(date -d "+$days days" +%Y-%m-%d)

    jq --arg pass "$new_pass" '.auth.config |= . + [$pass]' "$CONFIG_FILE" > /tmp/conf.tmp && mv /tmp/conf.tmp "$CONFIG_FILE"
    jq --arg user "$new_pass" --arg expired "$exp_date" '.accounts += [{"user":$user,"expired":$expired}]' "$META_FILE" > /tmp/meta.tmp && mv /tmp/meta.tmp "$META_FILE"

    systemctl restart "$SERVICE_NAME"

    echo "✅ Cuenta $new_pass agregada."
    read -rp "Presiona ENTER para volver al menú..." enter
    menu
}

eliminar_cuenta() {
    read -rp "Contraseña a eliminar: " del_pass
    # Verificar si la cuenta existe
    existe=$(jq -r --arg u "$del_pass" '.auth.config[] | select(.==$u)' "$CONFIG_FILE")
    if [ -z "$existe" ]; then
        echo "❌ Cuenta $del_pass no encontrada!"
    else
        jq --arg pass "$del_pass" '.auth.config |= map(select(. != $pass))' "$CONFIG_FILE" > /tmp/conf.tmp && mv /tmp/conf.tmp "$CONFIG_FILE"
        jq --arg pass "$del_pass" '.accounts |= map(select(.user != $pass))' "$META_FILE" > /tmp/meta.tmp && mv /tmp/meta.tmp "$META_FILE"
        systemctl restart "$SERVICE_NAME"
        echo "✅ Cuenta $del_pass eliminada."
    fi
    read -rp "Presiona ENTER para volver al menú..." enter
    menu
}

extender_cuenta() {
    read -rp "Contraseña de la cuenta: " ext_user
    [ -z "$ext_user" ] && menu

    # Obtener fecha de expiración anterior
    OLD_EXP=$(jq -r --arg u "$ext_user" '.accounts[] | select(.user==$u) | .expired' "$META_FILE")

    if [ -z "$OLD_EXP" ] || [ "$OLD_EXP" = "null" ]; then
        echo "❌ Cuenta $ext_user no encontrada!"
        read -rp "ENTER..." enter
        menu
    fi

    read -rp "Extender (días): " days
    [[ -z "$days" ]] && days=3

    HOY=$(date +%Y-%m-%d)

    # Determinar fecha base
    if [[ "$OLD_EXP" < "$HOY" ]]; then
        BASE_DATE="$HOY"
    else
        BASE_DATE="$OLD_EXP"
    fi

    NEW_EXP=$(date -d "$BASE_DATE +$days days" +%Y-%m-%d)

    jq --arg u "$ext_user" --arg exp "$NEW_EXP" '
      .accounts |= map(
        if .user == $u then
          .expired = $exp
        else .
        end
      )
    ' "$META_FILE" > /tmp/meta.tmp && mv /tmp/meta.tmp "$META_FILE"

    systemctl restart "$SERVICE_NAME"

    echo "✅ Cuenta extendida correctamente"
    echo "👤 Usuario    : $ext_user"
    echo "📅 Exp anterior: $OLD_EXP"
    echo "📅 Exp nueva   : $NEW_EXP"

    read -rp "ENTER..." enter
    menu
}

reiniciar_servicio() {
    systemctl restart "$SERVICE_NAME"
    sleep 1
    menu
}

estado_vps() {
    echo "Tiempo activo : $(uptime -p)"
    echo "Uso de CPU   : $(top -bn1 | grep Cpu | awk '{print $2 + $4 "%"}')"
    echo "Uso de RAM   : $(free -h | awk '/Mem:/ {print $3 " / " $2}')"
    echo "Uso de Disco : $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
    read -rp "Enter para continuar..." enter
    menu
}

menu
EOF

chmod +x "$MANAGER_SCRIPT"
echo -e "#!/bin/bash\nsudo $MANAGER_SCRIPT" > "$SHORTCUT"
chmod +x "$SHORTCUT"

# ============================
# 4️⃣ Script API y Servicio
# ============================
API_SCRIPT="/usr/local/bin/zivpn-api.sh"
cat <<'EOF' > "$API_SCRIPT"
#!/bin/bash

CONFIG="/etc/zivpn/config.json"
META="/etc/zivpn/accounts_meta.json"
SERVICE="zivpn.service"
IFACE=$(ip route | awk '/default/ {print $5}' | head -n1)
# Cargar ENV
ENV_FILE="/etc/zivpn/bot.env"
[ ! -f "$ENV_FILE" ] && { echo "Archivo ENV no encontrado"; exit 1; }
source "$ENV_FILE"

read request

CMD=$(echo "$request" | grep -oP '(?<=cmd=)[^& ]+')
KEY=$(echo "$request" | grep -oP '(?<=key=)[^& ]+')
USER=$(echo "$request" | grep -oP '(?<=user=)[^& ]+')
DAYS=$(echo "$request" | grep -oP '(?<=days=)[^& ]+')

[ -z "$DAYS" ] && DAYS=3

if [ "$KEY" != "$API_KEY" ]; then
  echo -e "HTTP/1.1 403 Forbidden\n\nClave API inválida"
  exit 0
fi

echo -e "HTTP/1.1 200 OK"
echo "Content-Type: text/plain"
echo ""

case "$CMD" in

list)
  jq -c ".accounts[]" "$META" | while read -r acc; do
    user=$(echo "$acc" | jq -r ".user")
    exp=$(echo "$acc" | jq -r ".expired")
    echo "• $user | Exp: $exp"
  done
;;

add)
  if [ -z "$USER" ]; then
    echo "❌ Parámetro usuario vacío"
    exit 0
  fi

  EXISTS=$(jq -r --arg u "$USER" '.auth.config[] | select(.==$u)' "$CONFIG")
  if [ -n "$EXISTS" ]; then
    echo "❌ Cuenta $USER ya existe"
    exit 0
  fi

  EXP_DATE=$(date -d "+$DAYS days" +%Y-%m-%d)

  jq --arg user "$USER" '.auth.config += [$user]' "$CONFIG" > /tmp/conf.tmp && mv /tmp/conf.tmp "$CONFIG"
  jq --arg user "$USER" --arg exp "$EXP_DATE" '.accounts += [{"user":$user,"expired":$exp}]' "$META" > /tmp/meta.tmp && mv /tmp/meta.tmp "$META"

  systemctl restart "$SERVICE"
  echo "✅ Cuenta $USER agregada correctamente (Exp: $EXP_DATE)"
;;

extend)
  if [ -z "$USER" ]; then
    echo "❌ Parámetro usuario vacío"
    exit 0
  fi

  OLD_EXP=$(jq -r --arg user "$USER" '.accounts[] | select(.user==$user) | .expired' "$META")

  if [ -z "$OLD_EXP" ] || [ "$OLD_EXP" = "null" ]; then
    echo "❌ Cuenta $USER no encontrada"
    exit 0
  fi

  TODAY=$(date +%Y-%m-%d)

  # Si ya expiró, calcular desde hoy
  if [[ "$OLD_EXP" < "$TODAY" ]]; then
    BASE_DATE="$TODAY"
  else
    BASE_DATE="$OLD_EXP"
  fi

  NEW_EXP=$(date -d "$BASE_DATE +$DAYS days" +%Y-%m-%d)

  jq --arg user "$USER" --arg exp "$NEW_EXP" '
    .accounts |= map(
      if .user == $user then
        .expired = $exp
      else .
      end
    )
  ' "$META" > /tmp/meta.tmp && mv /tmp/meta.tmp "$META"

  systemctl restart "$SERVICE"

  echo "✅ Cuenta $USER extendida correctamente"
  echo "📅 Expiración anterior: $OLD_EXP"
  echo "📅 Nueva expiración  : $NEW_EXP"
;;

delete)
  if [ -z "$USER" ]; then
    echo "❌ Parámetro usuario vacío"
    exit 0
  fi

  EXISTS=$(jq -r --arg u "$USER" '.auth.config[] | select(.==$u)' "$CONFIG")
  if [ -z "$EXISTS" ]; then
    echo "❌ Cuenta $USER no encontrada"
    exit 0
  fi

  jq --arg user "$USER" '.auth.config |= map(select(. != $user))' "$CONFIG" > /tmp/conf.tmp && mv /tmp/conf.tmp "$CONFIG"
  jq --arg user "$USER" '.accounts |= map(select(.user != $user))' "$META" > /tmp/meta.tmp && mv /tmp/meta.tmp "$META"

  systemctl restart "$SERVICE"
  echo "✅ Cuenta $USER eliminada correctamente"
;;

backup)
  cp "$CONFIG" /etc/zivpn/backup_config.json
  cp "$META" /etc/zivpn/backup_meta.json
  echo "✅ Respaldo EXITOSO"
;;

restore)
  if [ ! -f /etc/zivpn/backup_config.json ] || [ ! -f /etc/zivpn/backup_meta.json ]; then
    echo "❌ Respaldo no encontrado"
    exit 0
  fi

  cp /etc/zivpn/backup_config.json "$CONFIG"
  cp /etc/zivpn/backup_meta.json "$META"
  systemctl restart "$SERVICE"
  echo "✅ Restauración EXITOSA"
;;

restart)
  systemctl restart "$SERVICE"
  echo "✅ Servicio ZIVPN REINICIADO"
;;

status)
  echo "Tiempo activo : $(uptime -p)"
  echo "CPU           : $(top -bn1 | grep Cpu | awk '{print $2 + $4 "%"}')"
  echo "RAM           : $(free -h | awk '/Mem:/ {print $3 " / " $2}')"
  echo "Disco         : $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 ")"}')"
;;

bandwidth)
  RX=$(vnstat -i "$IFACE" --json | jq -r '.interfaces[0].traffic.day[-1].rx')
  TX=$(vnstat -i "$IFACE" --json | jq -r '.interfaces[0].traffic.day[-1].tx')
  RX=$(awk -v b=$RX 'BEGIN {printf "%.2f MB", b/1024/1024}')
  TX=$(awk -v b=$TX 'BEGIN {printf "%.2f MB", b/1024/1024}')
  echo "Diario Bajada: $RX"
  echo "Diario Subida: $TX"
;;

*)
  echo "Comando no reconocido"
;;

esac
EOF

chmod +x "$API_SCRIPT"

cat <<EOF > /etc/systemd/system/zivpn-api.service
[Unit]
Description=Servicio API ZIVPN
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:7001,bind=127.0.0.1,reuseaddr,fork EXEC:/usr/local/bin/zivpn-api.sh
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zivpn-api.service
systemctl restart zivpn-api.service

# ============================
# 5️⃣ Script del Bot de Telegram y Servicio
# ============================
BOT_SCRIPT="/usr/local/bin/zivpn-bot.sh"
cat <<'EOF' > "$BOT_SCRIPT"
#!/bin/bash
# BOT ZIVPN - PANEL INLINE
# chmod +x zivpn-bot.sh
# ./zivpn-bot.sh &

ENV_FILE="/etc/zivpn/bot.env"
[ ! -f "$ENV_FILE" ] && { echo "Archivo ENV no encontrado"; exit 1; }
source "$ENV_FILE"

CONFIG="/etc/zivpn/config.json"
META="/etc/zivpn/accounts_meta.json"
SERVICE="zivpn.service"
OFFSET_FILE="/tmp/zivpn_offset"
BACKUP_DIR="/etc/zivpn"

# Archivos de estado (por admin)
STATE_FILE="/tmp/zivpn_state_${ADMIN_ID}"
DATA_FILE="/tmp/zivpn_state_data_${ADMIN_ID}"

# Rastrear último ID de mensaje del bot
LAST_BOT_FILE="/tmp/zivpn_last_bot_${ADMIN_ID}"

# ---------------- Funciones de Telegram ----------------
tg_post() {
  local method="$1"; shift
  curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/$method" "$@"
}

delete_msg() {
  local msg_id="$1"
  [ -z "$msg_id" ] && return
  tg_post "deleteMessage" -d "chat_id=$ADMIN_ID" -d "message_id=$msg_id" >/dev/null 2>&1 || true
}

guardar_ultimo_bot() { echo -n "$1" > "$LAST_BOT_FILE"; }
obtener_ultimo_bot() { [ -f "$LAST_BOT_FILE" ] && cat "$LAST_BOT_FILE" || echo ""; }
limpiar_ultimo_bot() { rm -f "$LAST_BOT_FILE"; }

# Enviar mensaje y devolver respuesta JSON
enviar_msg_raw() {
  local TEXT="$1"
  local RM="$2"
  if [ -n "$RM" ]; then
    tg_post "sendMessage" \
      -d "chat_id=$ADMIN_ID" \
      --data-urlencode "text=$TEXT" \
      --data-urlencode "parse_mode=Markdown" \
      --data-urlencode "reply_markup=$RM"
  else
    tg_post "sendMessage" \
      -d "chat_id=$ADMIN_ID" \
      --data-urlencode "text=$TEXT" \
      --data-urlencode "parse_mode=Markdown"
  fi
}

# Reemplazar último mensaje del bot
reemplazar_mensaje_bot() {
  local TEXT="$1"
  local RM="$2"

  local last
  last="$(obtener_ultimo_bot)"
  [ -n "$last" ] && delete_msg "$last"
  limpiar_ultimo_bot

  local resp msgid
  resp="$(enviar_msg_raw "$TEXT" "$RM")"
  msgid="$(echo "$resp" | jq -r '.result.message_id // empty')"
  [ -n "$msgid" ] && guardar_ultimo_bot "$msgid"
}

responder_callback() {
  local CB_ID="$1"
  local TXT="$2"
  [ -z "$TXT" ] && TXT="OK"
  tg_post "answerCallbackQuery" \
    --data-urlencode "callback_query_id=$CB_ID" \
    --data-urlencode "text=$TXT" >/dev/null
}

enviar_archivo() {
  curl -s -F chat_id="$ADMIN_ID" -F document=@"$1" \
    "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" >/dev/null
}

obtener_updates() {
  local OFFSET=0
  [ -f "$OFFSET_FILE" ] && OFFSET=$(cat "$OFFSET_FILE")
  tg_post "getUpdates" -d "timeout=60" -d "offset=$OFFSET"
}

# ---------------- Verificar archivos base ----------------
[ ! -f "$CONFIG" ] && echo '{"auth":{"config":[]} }' > "$CONFIG"
[ ! -f "$META" ] && echo '{"accounts":[]}' > "$META"

# ---------------- Funciones de estado ----------------
set_state() { echo -n "$1" > "$STATE_FILE"; }
get_state() { [ -f "$STATE_FILE" ] && cat "$STATE_FILE" || echo ""; }
clear_state() { rm -f "$STATE_FILE" "$DATA_FILE"; }

set_pending_user() { echo -n "$1" > "$DATA_FILE"; }
get_pending_user() { [ -f "$DATA_FILE" ] && cat "$DATA_FILE" || echo ""; }

# ---------------- UI markups ----------------
RM_MENU='{"inline_keyboard":[
  [{"text":"📋 Listar Cuentas","callback_data":"LIST"},{"text":"🖥 Estado VPS","callback_data":"STATUS"}],
  [{"text":"📊 Ancho de Banda","callback_data":"BANDWIDTH"},{"text":"📂 Respaldar","callback_data":"BACKUP"}],
  [{"text":"♻️ Restaurar","callback_data":"RESTORE"}],
  [{"text":"🔁 Reiniciar Servicio","callback_data":"RESTART"}],
  [{"text":"➕ Agregar Usuario","callback_data":"ADD"},{"text":"🗑 Eliminar Usuario","callback_data":"DEL"}],
  [{"text":"🔄 Extender Cuenta","callback_data":"EXTEND"}]
]}'

RM_CANCEL='{"inline_keyboard":[
  [{"text":"❌ Cancelar","callback_data":"CANCEL"}],
  [{"text":"🏠 Menú","callback_data":"MENU"}]
]}'

# ---------------- Utilidades ----------------
formato_bytes() {
  local b=$1
  if [ -z "$b" ] || [ "$b" = "null" ]; then
    echo "0.00 MB"; return
  fi
  awk -v B="$b" 'BEGIN {
    MB = B/1024/1024;
    if (MB < 1024) printf "%.2f MB", MB;
    else printf "%.2f GB", MB/1024;
  }'
}

es_usuario_valido() {
  echo "$1" | grep -Eq '^[a-zA-Z0-9._-]{1,32}$'
}

# ---------------- Vistas (todas reemplazan mensaje) ----------------
mostrar_menu() {
  local txt="╔══════════════════════╗
        ✨ *PANEL ZIVPN PREMIUM* ✨
╚══════════════════════╝

Elige una opción abajo 👇"
  reemplazar_mensaje_bot "$txt" "$RM_MENU"
}

mostrar_lista() {
  local LISTA
  LISTA=$(jq -r '.accounts[]? | "👤 *\(.user)*     │ 🗓 Exp: *\(.expired)*"' "$META")
  [ -z "$LISTA" ] && LISTA="No hay cuentas"

  reemplazar_mensaje_bot "╔════════════════════╗
       📋 *LISTA DE CUENTAS PREMIUM*
╚════════════════════╝

$LISTA

──────────────────────
✨ Total cuentas: $(jq -r '.accounts | length' "$META")" "$RM_MENU"
}

mostrar_estado() {
  local CPU RAM DISCO TIEMPO_ACTIVO ISP IP_PUB
  CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8"%"}' 2>/dev/null || echo "N/A")
  RAM=$(free -h | awk '/Mem:/ {print $3 " / " $2}' 2>/dev/null || echo "N/A")
  DISCO=$(df -h / | awk 'NR==2 {print $5}' 2>/dev/null || echo "N/A")
  TIEMPO_ACTIVO=$(uptime -p 2>/dev/null || echo "N/A")
  ISP=$(curl -s https://ipinfo.io/org | sed 's/^[^ ]* //')
  IP_PUB=$(curl -sS https://api.ipify.org || echo "N/A")

  reemplazar_mensaje_bot "╔═════════════╗
          🖥 *ESTADO DEL VPS*
╚═════════════╝

⚡ *Uso de CPU*   : $CPU
🧠 *Uso de RAM*   : $RAM
💽 *Uso de Disco* : $DISCO
⏳ *Tiempo activo*: $TIEMPO_ACTIVO

📡 *Red*
• ISP       : $ISP
• IP Pública: $IP_PUB" "$RM_MENU"
}

mostrar_ancho_banda() {
  local NET_IFACE BW_DIARIO_BAJADA BW_DIARIO_SUBIDA BW_MENSUAL_BAJADA BW_MENSUAL_SUBIDA
  NET_IFACE=$(ip route | awk '/default/ {print $5}' | head -n1)

  if command -v vnstat >/dev/null 2>&1; then
    BW_DIARIO_BAJADA=$(vnstat -i "$NET_IFACE" --json | jq -r '.interfaces[0].traffic.day[-1].rx' 2>/dev/null)
    BW_DIARIO_SUBIDA=$(vnstat -i "$NET_IFACE" --json | jq -r '.interfaces[0].traffic.day[-1].tx' 2>/dev/null)
    BW_MENSUAL_BAJADA=$(vnstat -i "$NET_IFACE" --json | jq -r '.interfaces[0].traffic.month[-1].rx' 2>/dev/null)
    BW_MENSUAL_SUBIDA=$(vnstat -i "$NET_IFACE" --json | jq -r '.interfaces[0].traffic.month[-1].tx' 2>/dev/null)

    BW_DIARIO_BAJADA=$(formato_bytes "$BW_DIARIO_BAJADA")
    BW_DIARIO_SUBIDA=$(formato_bytes "$BW_DIARIO_SUBIDA")
    BW_MENSUAL_BAJADA=$(formato_bytes "$BW_MENSUAL_BAJADA")
    BW_MENSUAL_SUBIDA=$(formato_bytes "$BW_MENSUAL_SUBIDA")
  else
    BW_DIARIO_BAJADA="vnStat no instalado"
    BW_DIARIO_SUBIDA="vnStat no instalado"
    BW_MENSUAL_BAJADA="vnStat no instalado"
    BW_MENSUAL_SUBIDA="vnStat no instalado"
  fi

  reemplazar_mensaje_bot "╔══════════════════╗
        📊 *REPORTE DE ANCHO DE BANDA*
╚══════════════════╝

📅 *Diario*
⬇ Descarga : *$BW_DIARIO_BAJADA*
⬆ Subida   : *$BW_DIARIO_SUBIDA*

📆 *Mensual*
⬇ Descarga : *$BW_MENSUAL_BAJADA*
⬆ Subida   : *$BW_MENSUAL_SUBIDA*" "$RM_MENU"
}

mostrar_respaldo_completado() {
  reemplazar_mensaje_bot "╔═══════════════╗
     📂 *RESPALDO EXITOSO*
╚═══════════════╝

✔️ Archivo de configuración respaldado
✔️ Archivo de metadatos enviado

💠 Respaldo guardado de forma segura." "$RM_MENU"
}

mostrar_error() {
  reemplazar_mensaje_bot "$1" "$RM_MENU"
}

# ---------------- Acciones ----------------
respaldo_automatico() {
  cp "$CONFIG" "$BACKUP_DIR/backup_config.json"
  cp "$META" "$BACKUP_DIR/backup_meta.json"
  enviar_archivo "$BACKUP_DIR/backup_config.json"
  enviar_archivo "$BACKUP_DIR/backup_meta.json"
  mostrar_respaldo_completado
}

restaurar_respaldo() {
  local BC="$BACKUP_DIR/backup_config.json"
  local BM="$BACKUP_DIR/backup_meta.json"

  if [ ! -f "$BC" ] || [ ! -f "$BM" ]; then
    reemplazar_mensaje_bot "❌ *RESTAURACIÓN FALLIDA*

Los archivos de respaldo no existen.
Por favor, realiza primero un *Respaldo*." "$RM_MENU"
    return
  fi

  cp "$BC" "$CONFIG"
  cp "$BM" "$META"

  systemctl restart "$SERVICE"

  reemplazar_mensaje_bot "╔═══════════════════╗
     ♻️ *RESTAURACIÓN EXITOSA*
╚═══════════════════╝

✔️ Configuración restaurada
✔️ Datos de cuentas recuperados
🔁 Servicio reiniciado

✨ Sistema restaurado correctamente." "$RM_MENU"
}

agregar_usuario() {
  local USER="$1"
  local DAYS="$2"
  [[ ! "$DAYS" =~ ^[0-9]+$ ]] && DAYS=3

  local exists
  exists=$(jq -r --arg u "$USER" '.auth.config[]? | select(.==$u)' "$CONFIG")
  [ -n "$exists" ] && mostrar_error "❗ El usuario *$USER* ya existe!" && return

  local EXP
  EXP=$(date -d "+$DAYS days" +%Y-%m-%d)

  jq --arg p "$USER" '.auth.config += [$p]' "$CONFIG" > /tmp/conf && mv /tmp/conf "$CONFIG"
  jq --arg u "$USER" --arg e "$EXP" '.accounts += [{"user":$u,"expired":$e}]' "$META" > /tmp/meta && mv /tmp/meta "$META"

  systemctl restart "$SERVICE"
  reemplazar_mensaje_bot "╔═══════════════════╗
     ✅ *CUENTA CREADA EXITOSAMENTE*
╚═══════════════════╝

👤 Usuario : *$USER*
🗓 Expira  : *$EXP*

✨ ¡Felicidades! La cuenta está lista para usar." "$RM_MENU"
}

eliminar_usuario() {
  local USER="$1"

  local exists
  exists=$(jq -r --arg u "$USER" '.auth.config[]? | select(.==$u)' "$CONFIG")
  [ -z "$exists" ] && mostrar_error "❗ El usuario *$USER* no existe!" && return

  jq --arg p "$USER" '.auth.config |= map(select(. != $p))' "$CONFIG" > /tmp/conf && mv /tmp/conf "$CONFIG"
  jq --arg u "$USER" '.accounts |= map(select(.user != $u))' "$META" > /tmp/meta && mv /tmp/meta "$META"

  systemctl restart "$SERVICE"
  reemplazar_mensaje_bot "╔═════════════╗
     🗑️ *CUENTA ELIMINADA*
╚═════════════╝

👤 Usuario : *$USER*

✅ Proceso de eliminación completado." "$RM_MENU"
}

extender_usuario() {
  local USER="$1"
  local DAYS="$2"
  local EXP_ACTUAL
  EXP_ACTUAL=$(jq -r --arg u "$USER" '.accounts[] | select(.user == $u) | .expired' "$META")

  if [ -z "$EXP_ACTUAL" ]; then
    mostrar_error "❗ La cuenta *$USER* no existe!"
    return
  fi

  # Extender cuenta
  local NUEVA_EXP
  NUEVA_EXP=$(date -d "$EXP_ACTUAL +$DAYS days" +%Y-%m-%d)

  jq --arg u "$USER" --arg e "$NUEVA_EXP" '
    .accounts |= map(
      if .user == $u then
        .expired = $e
      else .
      end
    )
  ' "$META" > /tmp/meta && mv /tmp/meta "$META"

  systemctl restart "$SERVICE"

  reemplazar_mensaje_bot "╔═══════════════════╗
     ✅ *CUENTA EXTENDIDA EXITOSAMENTE*
╚═══════════════════╝

👤 Usuario : *$USER*
📅 Expiración: *$EXP_ACTUAL* ➡ *$NUEVA_EXP*

✨ ¡Cuenta extendida correctamente!" "$RM_MENU"
}

# ---------------- Bucle principal ----------------
mostrar_menu

while true; do
  UPDATES=$(obtener_updates)

  echo "$UPDATES" | jq -c '.result[]' 2>/dev/null | while read -r row; do
    UPDATE_ID=$(echo "$row" | jq -r '.update_id')
    [ -n "$UPDATE_ID" ] && echo $((UPDATE_ID + 1)) > "$OFFSET_FILE"

    CHAT=$(echo "$row" | jq -r '.message.chat.id // .callback_query.message.chat.id // empty')
    TEXT=$(echo "$row" | jq -r '.message.text // empty')
    CB_DATA=$(echo "$row" | jq -r '.callback_query.data // empty')
    CB_ID=$(echo "$row" | jq -r '.callback_query.id // empty')
    CLICKED_MSG_ID=$(echo "$row" | jq -r '.callback_query.message.message_id // empty')

    [ "$CHAT" != "$ADMIN_ID" ] && continue
    [ -z "$TEXT" ] && [ -z "$CB_DATA" ] && continue

    # ---- En cada clic: eliminar el mensaje clickeado, luego enviar nuevo ----
    if [ -n "$CB_DATA" ]; then
      responder_callback "$CB_ID" "OK"

      # eliminar mensaje clickeado
      if [ -n "$CLICKED_MSG_ID" ]; then
        delete_msg "$CLICKED_MSG_ID"
        # evitar intentar eliminarlo nuevamente
        last="$(obtener_ultimo_bot)"
        if [ "$last" = "$CLICKED_MSG_ID" ]; then
          limpiar_ultimo_bot
        fi
      fi

      case "$CB_DATA" in
        "MENU")
          clear_state
          mostrar_menu
          ;;
        "CANCEL")
          clear_state
          mostrar_menu
          ;;
        "LIST")
          clear_state
          mostrar_lista
          ;;
        "STATUS")
          clear_state
          mostrar_estado
          ;;
        "BANDWIDTH")
          clear_state
          mostrar_ancho_banda
          ;;
        "BACKUP")
          clear_state
          respaldo_automatico
          ;;
        "RESTORE")
          clear_state
          set_state "RESTORE_CONFIRM"
          reemplazar_mensaje_bot "⚠️ *CONFIRMAR RESTAURACIÓN*

         La restauración:
         • Sobrescribirá la configuración actual
         • Recuperará las cuentas del respaldo

         Escribe: *YES* para continuar" "$RM_CANCEL"
           ;;
        "RESTART")
          clear_state
          systemctl restart "$SERVICE" \
            && reemplazar_mensaje_bot "🔁 Servicio *$SERVICE* reiniciado." "$RM_MENU" \
            || reemplazar_mensaje_bot "❌ Fallo al reiniciar el servicio." "$RM_MENU"
          ;;
        "ADD")
          clear_state
          set_state "ADD_WAIT_USER"
          reemplazar_mensaje_bot "╔═══════════════════╗
     ➕ *AGREGAR CUENTA*
╚═══════════════════╝
Envía el *nombre de usuario* (sin espacios)
Ejemplo: \`ziziv\`" "$RM_CANCEL"
          ;;
        "DEL")
          clear_state
          set_state "DEL_WAIT_USER"
          reemplazar_mensaje_bot "╔═══════════════════╗
     🗑️ *ELIMINAR CUENTA*
╚═══════════════════╝
Envía el *nombre de usuario* a eliminar
Ejemplo: \`ziziv\`" "$RM_CANCEL"
          ;;
        "EXTEND")
          clear_state
          set_state "EXTEND_WAIT_USER"
          reemplazar_mensaje_bot "╔═══════════════════╗
     🔄 *EXTENDER CUENTA*
╚═══════════════════╝
Envía el *nombre de usuario* a extender
Ejemplo: \`ziziv\`" "$RM_CANCEL"
          ;;
      esac
      continue
    fi

    # ---- Flujo de entrada de texto (interactivo add/del/extend) ----
    ESTADO=$(get_state)
    if [ -n "$ESTADO" ]; then
      case "$ESTADO" in
        "ADD_WAIT_USER")
          USERNAME="$TEXT"
          if ! es_usuario_valido "$USERNAME"; then
            reemplazar_mensaje_bot "❗ *Nombre de usuario inválido*\nUsa: letras/números/punto/guion_bajo/guion\nSin espacios (máx 32 caracteres)\nEjemplo: \`usuario01\`" "$RM_CANCEL"
            continue
          fi
          set_pending_user "$USERNAME"
          set_state "ADD_WAIT_DAYS"
          reemplazar_mensaje_bot "╔═══════════════════╗
      🗓 *DURACIÓN DE LA CUENTA*
╚═══════════════════╝
Usuario: *$USERNAME*
Envía el número de *días* (solo números)
Por defecto: *3*
Ejemplo: \`7\`" "$RM_CANCEL"
          continue
          ;;
        "ADD_WAIT_DAYS")
          USERNAME="$(get_pending_user)"
          DAYS="$TEXT"
          [[ ! "$DAYS" =~ ^[0-9]+$ ]] && DAYS=3
          clear_state
          agregar_usuario "$USERNAME" "$DAYS"
          continue
          ;;
        "DEL_WAIT_USER")
          USERNAME="$TEXT"
          if ! es_usuario_valido "$USERNAME"; then
            reemplazar_mensaje_bot "❗ Nombre de usuario inválido.\nEjemplo: \`usuario01\`" "$RM_CANCEL"
            continue
          fi
          clear_state
          eliminar_usuario "$USERNAME"
          continue
          ;;
        "EXTEND_WAIT_USER")
          USERNAME="$TEXT"
          if ! es_usuario_valido "$USERNAME"; then
            reemplazar_mensaje_bot "❗ Nombre de usuario inválido.\nEjemplo: \`ziziv\`" "$RM_CANCEL"
            continue
          fi
          set_pending_user "$USERNAME"
          set_state "EXTEND_WAIT_DAYS"
          reemplazar_mensaje_bot "╔═══════════════════╗
      🗓 *DURACIÓN DE EXTENSIÓN*
╚═══════════════════╝
Usuario: *$USERNAME*
Envía el número de *días* a extender (solo números)
Por defecto: *3*
Ejemplo: \`7\`" "$RM_CANCEL"
          continue
          ;;
        "RESTORE_CONFIRM")
         if [ "$TEXT" = "YES" ]; then
           clear_state
           restaurar_respaldo
         else
          clear_state
          reemplazar_mensaje_bot "❌ Restauración cancelada." "$RM_MENU"
         fi
         continue
          ;;
        "EXTEND_WAIT_DAYS")
          USERNAME="$(get_pending_user)"
          DAYS="$TEXT"
          [[ ! "$DAYS" =~ ^[0-9]+$ ]] && DAYS=3
          clear_state
          extender_usuario "$USERNAME" "$DAYS"
          continue
          ;;
      esac
    fi

    # si el admin escribe texto aleatorio mientras está inactivo, solo mostrar menú
    mostrar_menu
  done
done
EOF

chmod +x "$BOT_SCRIPT"

cat <<EOF > /etc/systemd/system/zivpn-bot.service
[Unit]
Description=Bot de Telegram ZIVPN
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zivpn-bot.sh
Restart=always
RestartSec=3
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable zivpn-bot.service
systemctl start zivpn-bot.service

# ============================
# 6️⃣ Eliminación automática de expirados 24/7
# ============================

echo "Creando script de eliminación automática de expirados..."

cat <<'EOF' > /usr/local/bin/zivpn-autoremove.sh
#!/bin/bash
CONFIG_FILE="/etc/zivpn/config.json"
META_FILE="/etc/zivpn/accounts_meta.json"
SERVICE_NAME="zivpn.service"

hoy=$(date +%s)

jq -c ".accounts[]" "$META_FILE" | while read -r acc; do
    user=$(echo "$acc" | jq -r ".user")
    exp=$(echo "$acc" | jq -r ".expired")
    exp_epoch=$(date -d "$exp" +%s 2>/dev/null)

    if [ "$hoy" -ge "$exp_epoch" ]; then
        jq --arg user "$user" '.auth.config |= map(select(. != $user))' \
            "$CONFIG_FILE" > /tmp/config.tmp && mv /tmp/config.tmp "$CONFIG_FILE"

        jq --arg user "$user" '.accounts |= map(select(.user != $user))' \
            "$META_FILE" > /tmp/meta.tmp && mv /tmp/meta.tmp "$META_FILE"

        systemctl restart "$SERVICE_NAME" >/dev/null 2>&1
        echo "$(date) Auto eliminado usuario expirado: $user" >> /var/log/zivpn-autoremove.log
    fi
done
EOF

chmod +x /usr/local/bin/zivpn-autoremove.sh

# Agregar tarea cron cada hora
(crontab -l 2>/dev/null | grep -v 'zivpn-autoremove.sh'; echo "0 * * * * /usr/local/bin/zivpn-autoremove.sh >/dev/null 2>&1") | crontab -

# ============================
# 7️⃣ Finalizado
# ============================
echo "===================================="
echo "✅ ¡ZIVPN Manager + API + Bot Instalado!"
echo "Manager: zivpn-manager"
echo "Configura el Bot de Telegram en el Manager"
echo "Eliminación automática de expirados: ACTIVADA"
echo "===================================="
echo ""
echo "🚀 Abriendo ZIVPN Manager..."
sleep 2
zivpn-manager