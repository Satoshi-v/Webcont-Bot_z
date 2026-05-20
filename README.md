ZIVPN Manager VPS y Bot de Telegram

Requisitos previos

⚠️ OBLIGATORIO asegurarse de que UDP ZIVPN ya esté instalado y funcionando en el VPS.

⚠️ OBLIGATORIO tener preparado el ID de Administrador y el Token del Bot de Telegram.

⚠️ OBLIGATORIO cambiar el ID de Administrador, Token del Bot y Clave API en zivpn-manager.

⚠️ Si UDP ZIVPN no está instalado, instálalo primero.

⚠️ El Manager VPS y el Bot de Telegram no funcionarán correctamente sin UDP ZIVPN.

---

*Instalar UDP ZIVPN (obligatorio)

Servidor UDP para la aplicación ZIVPN Tunnel (SSH/DNS/UDP) VPN.

Binario del servidor para Linux amd64 y arm.

Instalación Zizi AMD

```bash
wget -O zi.sh https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/zi.sh; sudo chmod +x zi.sh; sudo ./zi.sh
```

Instalación Zizi ARM

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/zi2.sh)
```

Desinstalar Zizi

```bash
sudo wget -O ziun.sh https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/uninstall.sh; sudo chmod +x ziun.sh; sudo ./ziun.sh
```

---

*Instalar Manager VPS + Bot de Telegram

Instalación

Ejecuta el siguiente comando como root en el VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/Satoshi-v/Webcont-Bot_z/main/bot_z.sh -o bot_z.sh
chmod +x bot_z.sh
./bot_z.sh
```

O en una sola línea:

```bash
curl -fsSL https://raw.githubusercontent.com/Satoshi-v/Webcont-Bot_z/main/bot_z.sh -o bot_z.sh && chmod +x bot_z.sh && ./bot_z.sh
```

---

*Instalar UDPGW

Instalación

Ejecuta el siguiente comando como root en el VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/harunkl/zivpn-manager-bot/main/install-udpgw.sh | sudo bash
```

---

*Notas importantes

· Asegúrate de que el VPS tenga acceso a internet normal
· El script configurará el Manager VPS y el Bot de Telegram automáticamente
· Se recomienda usar un VPS nuevo / sin muchos otros servicios instalados

---

*Configuración después de la instalación

1. Edita la configuración del bot:
   ```bash
   nano /etc/zivpn/bot.env
   ```
   · Cambia TOKEN_DEL_BOT_AQUI por tu token de Telegram
   · Cambia ID_DEL_ADMIN_AQUI por tu ID de usuario
2. Reinicia los servicios:
   ```bash
   systemctl restart zivpn-bot.service
   systemctl restart zivpn-api.service
   ```
3. Abre el panel de gestión:
   ```bash
   zivpn-manager
   ```

---

*Comandos útiles

Comando Descripción
zivpn-manager Abre el panel de gestión
systemctl status zivpn-bot Ver estado del bot
systemctl status zivpn-api Ver estado de la API
systemctl restart zivpn-bot Reiniciar el bot
journalctl -u zivpn-bot -f Ver logs del bot en tiempo real

---

*Obtener credenciales de Telegram

· Token del Bot: Habla con @BotFather en Telegram
· ID de Administrador: Escribe a @userinfobot

---
