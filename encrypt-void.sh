#!/bin/bash
# =============================================================================
#  Void Linux Installer - GRUB + ext4 + LVM sobre LUKS
#  Suporte a XFCE4 ou MATE + gerenciador de login
#  Autor: gerado por Claude
#  Uso: boot pelo live ISO do Void, execute como root
# =============================================================================

set -euo pipefail

# ── Cores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[AVISO]${NC} $*"; }
error()   { echo -e "${RED}[ERRO]${NC} $*"; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; \
             echo -e "${BOLD}${CYAN}  $*${NC}"; \
             echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"; }

# ── Verificações iniciais ─────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Execute como root (sudo ou su -)"
command -v xbps-install &>/dev/null || error "Este script deve rodar dentro do live ISO do Void Linux"

# ── Detectar modo de boot ──────────────────────────────────────────────────────
if [[ -d /sys/firmware/efi/efivars ]]; then
    BOOT_MODE="uefi"
    info "Modo de boot detectado: UEFI"
else
    BOOT_MODE="bios"
    info "Modo de boot detectado: BIOS/Legacy"
fi

# =============================================================================
#  ETAPA 1 — Escolha do disco
# =============================================================================
header "DISCOS DISPONÍVEIS"

lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E "^(sd|vd|nvme|mmcblk)" || true
echo ""
echo -e "${BOLD}Dispositivos completos:${NC}"
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -v "loop"
echo ""

while true; do
    read -rp "$(echo -e "${BOLD}Digite o disco alvo (ex: sda, nvme0n1): ${NC}")" DISK_NAME
    DISK="/dev/${DISK_NAME}"
    [[ -b "$DISK" ]] && break
    warn "Dispositivo '$DISK' não encontrado. Tente novamente."
done

ok "Disco selecionado: $DISK"
warn "TODO O CONTEÚDO DE $DISK SERÁ APAGADO!"
read -rp "Tem certeza? Digite 'SIM' para continuar: " CONFIRM
[[ "$CONFIRM" != "SIM" ]] && error "Instalação cancelada pelo usuário."

# =============================================================================
#  ETAPA 2 — Criptografia?
# =============================================================================
header "CRIPTOGRAFIA"

ENCRYPT=false
read -rp "$(echo -e "${BOLD}Deseja usar criptografia LUKS+LVM? [s/N]: ${NC}")" USE_CRYPT
if [[ "$USE_CRYPT" =~ ^[Ss]$ ]]; then
    ENCRYPT=true
    ok "Instalação criptografada ativada (LUKS + LVM)"
else
    info "Instalação sem criptografia"
fi

# =============================================================================
#  ETAPA 3 — Desktop Environment
# =============================================================================
header "AMBIENTE DE DESKTOP"

echo "  1) XFCE4  (leve, rápido)"
echo "  2) MATE   (clássico, familiar)"
echo ""
while true; do
    read -rp "$(echo -e "${BOLD}Escolha [1/2]: ${NC}")" DE_CHOICE
    case "$DE_CHOICE" in
        1) DE="xfce4"; DM="lightdm"; break ;;
        2) DE="mate";  DM="lightdm"; break ;;
        *) warn "Opção inválida." ;;
    esac
done
ok "Desktop selecionado: $DE com $DM"

# =============================================================================
#  ETAPA 4 — Dados do sistema
# =============================================================================
header "CONFIGURAÇÃO DO SISTEMA"

read -rp "$(echo -e "${BOLD}Hostname: ${NC}")" HOSTNAME
[[ -z "$HOSTNAME" ]] && HOSTNAME="voidlinux"

read -rp "$(echo -e "${BOLD}Nome do usuário: ${NC}")" USERNAME
[[ -z "$USERNAME" ]] && USERNAME="user"

while true; do
    read -rsp "$(echo -e "${BOLD}Senha do usuário '$USERNAME': ${NC}")" USER_PASS; echo
    read -rsp "$(echo -e "${BOLD}Confirme a senha: ${NC}")" USER_PASS2; echo
    [[ "$USER_PASS" == "$USER_PASS2" ]] && break
    warn "Senhas não coincidem. Tente novamente."
done

while true; do
    read -rsp "$(echo -e "${BOLD}Senha do root: ${NC}")" ROOT_PASS; echo
    read -rsp "$(echo -e "${BOLD}Confirme senha do root: ${NC}")" ROOT_PASS2; echo
    [[ "$ROOT_PASS" == "$ROOT_PASS2" ]] && break
    warn "Senhas não coincidem. Tente novamente."
done

if $ENCRYPT; then
    while true; do
        read -rsp "$(echo -e "${BOLD}Senha de desbloqueio LUKS (anote com cuidado!): ${NC}")" LUKS_PASS; echo
        read -rsp "$(echo -e "${BOLD}Confirme senha LUKS: ${NC}")" LUKS_PASS2; echo
        [[ "$LUKS_PASS" == "$LUKS_PASS2" ]] && break
        warn "Senhas não coincidem. Tente novamente."
    done
fi

echo ""
read -rp "$(echo -e "${BOLD}Fuso horário (ex: America/Sao_Paulo): ${NC}")" TIMEZONE
[[ -z "$TIMEZONE" ]] && TIMEZONE="America/Sao_Paulo"

echo ""
read -rp "$(echo -e "${BOLD}Locale (ex: pt_BR.UTF-8): ${NC}")" LOCALE
[[ -z "$LOCALE" ]] && LOCALE="pt_BR.UTF-8"

# =============================================================================
#  ETAPA 5 — Resumo e confirmação final
# =============================================================================
header "RESUMO DA INSTALAÇÃO"

echo -e "  Disco alvo   : ${BOLD}$DISK${NC}"
echo -e "  Modo boot    : ${BOLD}${BOOT_MODE^^}${NC}"
echo -e "  Criptografia : ${BOLD}$($ENCRYPT && echo 'SIM (LUKS+LVM)' || echo 'NÃO')${NC}"
echo -e "  Desktop      : ${BOLD}${DE^^}${NC}"
echo -e "  Hostname     : ${BOLD}$HOSTNAME${NC}"
echo -e "  Usuário      : ${BOLD}$USERNAME${NC}"
echo -e "  Fuso horário : ${BOLD}$TIMEZONE${NC}"
echo -e "  Locale       : ${BOLD}$LOCALE${NC}"
echo ""
warn "Esta é sua última chance antes de apagar o disco!"
read -rp "Iniciar instalação? Digite 'INSTALAR' para confirmar: " FINAL_CONFIRM
[[ "$FINAL_CONFIRM" != "INSTALAR" ]] && error "Instalação cancelada."

# =============================================================================
#  ETAPA 6 — Particionamento
# =============================================================================
header "PARTICIONANDO $DISK"

# Zera assinaturas antigas
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"

if [[ "$BOOT_MODE" == "uefi" ]]; then
    info "Criando tabela GPT (UEFI)"
    sgdisk -n 1:0:+512M  -t 1:ef00 -c 1:"EFI"  "$DISK"   # EFI
    sgdisk -n 2:0:+1G    -t 2:8300 -c 2:"boot" "$DISK"   # /boot
    sgdisk -n 3:0:0      -t 3:8300 -c 3:"root" "$DISK"   # / (ou LUKS)

    # Nomes das partições (nvme usa p1, p2; sda usa sda1, sda2)
    if [[ "$DISK_NAME" == nvme* ]] || [[ "$DISK_NAME" == mmcblk* ]]; then
        PART_EFI="${DISK}p1"
        PART_BOOT="${DISK}p2"
        PART_ROOT="${DISK}p3"
    else
        PART_EFI="${DISK}1"
        PART_BOOT="${DISK}2"
        PART_ROOT="${DISK}3"
    fi

    mkfs.fat -F32 -n EFI "$PART_EFI"
    ok "Partição EFI formatada"
else
    info "Criando tabela MBR (BIOS/Legacy)"
    sgdisk -n 1:0:+1M    -t 1:ef02 -c 1:"bios" "$DISK"   # BIOS boot
    sgdisk -n 2:0:+512M  -t 2:8300 -c 2:"boot" "$DISK"   # /boot
    sgdisk -n 3:0:0      -t 3:8300 -c 3:"root" "$DISK"   # /

    if [[ "$DISK_NAME" == nvme* ]] || [[ "$DISK_NAME" == mmcblk* ]]; then
        PART_BOOT="${DISK}p2"
        PART_ROOT="${DISK}p3"
    else
        PART_BOOT="${DISK}2"
        PART_ROOT="${DISK}3"
    fi
fi

mkfs.ext4 -L boot "$PART_BOOT"
ok "Partição /boot formatada (ext4)"

# =============================================================================
#  ETAPA 7 — LUKS + LVM (se criptografia ativada)
# =============================================================================
if $ENCRYPT; then
    header "CONFIGURANDO LUKS + LVM"

    info "Formatando container LUKS..."
    echo -n "$LUKS_PASS" | cryptsetup luksFormat \
        --type luks2 \
        --cipher aes-xts-plain64 \
        --key-size 512 \
        --hash sha512 \
        --pbkdf argon2id \
        "$PART_ROOT" -

    info "Abrindo container LUKS..."
    echo -n "$LUKS_PASS" | cryptsetup open "$PART_ROOT" cryptlvm -

    LUKS_UUID=$(blkid -s UUID -o value "$PART_ROOT")
    LVM_DEV="/dev/mapper/cryptlvm"

    info "Criando LVM..."
    pvcreate "$LVM_DEV"
    vgcreate vgvoid "$LVM_DEV"
    lvcreate -l 100%FREE vgvoid -n root

    PART_REALROOT="/dev/vgvoid/root"
    ok "LVM configurado: /dev/vgvoid/root"
else
    PART_REALROOT="$PART_ROOT"
fi

# =============================================================================
#  ETAPA 8 — Formatar e montar raiz
# =============================================================================
header "FORMATANDO E MONTANDO"

mkfs.ext4 -L void-root "$PART_REALROOT"
ok "Partição raiz formatada (ext4)"

mount "$PART_REALROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_BOOT" /mnt/boot

if [[ "$BOOT_MODE" == "uefi" ]]; then
    mkdir -p /mnt/boot/efi
    mount "$PART_EFI" /mnt/boot/efi
fi

ok "Sistema de arquivos montado em /mnt"

# =============================================================================
#  ETAPA 9 — Instalação base via XBPS
# =============================================================================
header "INSTALANDO SISTEMA BASE"

# Mirror Brasil (ou global se falhar)
MIRROR="https://repo-default.voidlinux.org/current"

XBPS_ARCH=$(xbps-uhelper arch)
info "Arquitetura: $XBPS_ARCH"

BASE_PKGS=(
    base-system
    grub
    grub-x86_64-efi   # removido se bios
    os-prober
    lvm2
    cryptsetup
    linux
    linux-headers
    vim
    nano
    curl
    wget
    git
    bash-completion
    NetworkManager
    network-manager-applet
    dbus
    elogind
    polkit
    xorg
    xorg-server
    xinit
    lightdm
    lightdm-gtk3-greeter
)

# Remove grub-x86_64-efi se BIOS
if [[ "$BOOT_MODE" == "bios" ]]; then
    BASE_PKGS=("${BASE_PKGS[@]/grub-x86_64-efi/}")
fi

# Pacotes do DE escolhido
if [[ "$DE" == "xfce4" ]]; then
    DE_PKGS=(
        xfce4
        xfce4-plugins
        xfce4-terminal
        xfce4-screenshooter
        thunar
        thunar-archive-plugin
        mousepad
        ristretto
        xarchiver
        pavucontrol
        gvfs
        gvfs-mtp
        network-manager-applet
        xfce4-notifyd
        xfce4-pulseaudio-plugin
        pulseaudio
    )
else
    DE_PKGS=(
        mate
        mate-extra
        mate-terminal
        pluma
        eom
        engrampa
        mate-media
        pavucontrol
        gvfs
        gvfs-mtp
        network-manager-applet
        pulseaudio
    )
fi

ALL_PKGS=("${BASE_PKGS[@]}" "${DE_PKGS[@]}")

info "Instalando pacotes (pode demorar alguns minutos)..."
XBPS_ARCH="$XBPS_ARCH" xbps-install \
    -S \
    -R "$MIRROR" \
    -r /mnt \
    "${ALL_PKGS[@]}" || error "Falha na instalação dos pacotes base"

ok "Pacotes instalados com sucesso"

# =============================================================================
#  ETAPA 10 — Configuração do sistema
# =============================================================================
header "CONFIGURANDO O SISTEMA"

# fstab
info "Gerando /etc/fstab..."
{
    echo "# /etc/fstab gerado pelo void-install.sh"
    echo ""
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        EFI_UUID=$(blkid -s UUID -o value "$PART_EFI")
        echo "UUID=$EFI_UUID  /boot/efi  vfat  defaults  0 2"
    fi
    BOOT_UUID=$(blkid -s UUID -o value "$PART_BOOT")
    ROOT_UUID=$(blkid -s UUID -o value "$PART_REALROOT")
    echo "UUID=$BOOT_UUID  /boot  ext4  defaults  0 2"
    echo "UUID=$ROOT_UUID  /      ext4  defaults  0 1"
    echo "tmpfs  /tmp  tmpfs  defaults,nosuid,nodev  0 0"
} > /mnt/etc/fstab
ok "/etc/fstab criado"

# hostname
echo "$HOSTNAME" > /mnt/etc/hostname
ok "Hostname: $HOSTNAME"

# locale
echo "LANG=$LOCALE" > /mnt/etc/locale.conf
echo "$LOCALE UTF-8" >> /mnt/etc/default/libc-locales
ok "Locale: $LOCALE"

# timezone
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /mnt/etc/localtime
ok "Timezone: $TIMEZONE"

# rc.conf
cat > /mnt/etc/rc.conf <<EOF
TIMEZONE="$TIMEZONE"
KEYMAP="br-abnt2"
FONT="Lat2-Terminus16"
HARDWARECLOCK="UTC"
EOF
ok "rc.conf configurado"

# /etc/hosts
cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
EOF
ok "/etc/hosts configurado"

# crypttab (só se criptografado)
if $ENCRYPT; then
    echo "cryptlvm  UUID=$LUKS_UUID  none  luks" > /mnt/etc/crypttab
    ok "/etc/crypttab configurado"
fi

# =============================================================================
#  ETAPA 11 — chroot: senhas, usuário, serviços, GRUB, dracut
# =============================================================================
header "CONFIGURANDO DENTRO DO CHROOT"

# Montar pseudo-filesystems
mount --rbind /sys  /mnt/sys;  mount --make-rslave /mnt/sys
mount --rbind /dev  /mnt/dev;  mount --make-rslave /mnt/dev
mount --rbind /proc /mnt/proc; mount --make-rslave /mnt/proc

# Copiar resolv.conf para ter rede dentro do chroot
cp /etc/resolv.conf /mnt/etc/resolv.conf

# Script executado dentro do chroot
CHROOT_SCRIPT=$(cat <<CHROOT_EOF
#!/bin/bash
set -euo pipefail

# Locale
xbps-reconfigure -f glibc-locales

# Senhas
echo "root:${ROOT_PASS}" | chpasswd
useradd -m -G wheel,audio,video,optical,storage,network,plugdev -s /bin/bash "${USERNAME}"
echo "${USERNAME}:${USER_PASS}" | chpasswd

# Sudo para wheel
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel

# Serviços essenciais
ln -sf /etc/sv/dbus          /etc/runit/runsvdir/default/
ln -sf /etc/sv/elogind       /etc/runit/runsvdir/default/
ln -sf /etc/sv/NetworkManager /etc/runit/runsvdir/default/
ln -sf /etc/sv/lightdm       /etc/runit/runsvdir/default/

# Sessão padrão do LightDM
GREETER_CFG="/etc/lightdm/lightdm-gtk-greeter.conf"
if [[ ! -f "\$GREETER_CFG" ]]; then
    mkdir -p /etc/lightdm
    echo "[greeter]" > "\$GREETER_CFG"
fi

LIGHTDM_CFG="/etc/lightdm/lightdm.conf"
if grep -q "^\[Seat:\*\]" "\$LIGHTDM_CFG" 2>/dev/null; then
    sed -i "s|^#*user-session=.*|user-session=${DE}|" "\$LIGHTDM_CFG"
else
    printf '\n[Seat:*]\nuser-session=${DE}\n' >> "\$LIGHTDM_CFG"
fi

# Dracut (initramfs com suporte a LUKS+LVM)
DRACUT_CONF="/etc/dracut.conf.d/void.conf"
mkdir -p /etc/dracut.conf.d
cat > "\$DRACUT_CONF" <<DRACUT
hostonly=yes
hostonly_cmdline=yes
add_dracutmodules+=" crypt dm lvm resume "
omit_dracutmodules+=" network "
DRACUT

$(if $ENCRYPT; then
echo '
LUKS_UUID_INNER="'"$LUKS_UUID"'"
echo "rd.luks.uuid=\$LUKS_UUID_INNER rd.lvm.vg=vgvoid" >> /etc/kernel/cmdline 2>/dev/null || true
'
fi)

# Gerar initramfs
dracut --force --kver \$(ls /lib/modules | tail -1)

# GRUB
$(if [[ "$BOOT_MODE" == "uefi" ]]; then
echo 'grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=VOID'
else
echo "grub-install --target=i386-pc $DISK"
fi)

# Configurar GRUB
$(if $ENCRYPT; then
echo "
GRUB_CRYPT_LINE=\"GRUB_CMDLINE_LINUX=\\\"rd.luks.uuid=$LUKS_UUID rd.lvm.vg=vgvoid root=/dev/vgvoid/root\\\"\"
sed -i \"s|^GRUB_CMDLINE_LINUX=.*|\$GRUB_CRYPT_LINE|\" /etc/default/grub
echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
"
fi)

sed -i 's/^#GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub 2>/dev/null || true
update-grub

echo "CHROOT_OK"
CHROOT_EOF
)

echo "$CHROOT_SCRIPT" > /mnt/tmp/chroot-setup.sh
chmod +x /mnt/tmp/chroot-setup.sh

RESULT=$(chroot /mnt /tmp/chroot-setup.sh 2>&1) || {
    echo "$RESULT"
    error "Falha dentro do chroot. Veja os erros acima."
}

echo "$RESULT" | grep -v "^$" | tail -20
[[ "$RESULT" == *"CHROOT_OK"* ]] && ok "Configuração dentro do chroot concluída" || warn "Verifique a saída acima"

rm -f /mnt/tmp/chroot-setup.sh

# =============================================================================
#  ETAPA 12 — Finalização
# =============================================================================
header "FINALIZANDO"

info "Desmontando sistemas de arquivos..."
umount -R /mnt 2>/dev/null || true
if $ENCRYPT; then
    vgchange -an vgvoid 2>/dev/null || true
    cryptsetup close cryptlvm 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   INSTALAÇÃO CONCLUÍDA COM SUCESSO! 🎉  ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Desktop   : ${BOLD}${DE^^}${NC}"
echo -e "  Usuário   : ${BOLD}$USERNAME${NC}"
echo -e "  Hostname  : ${BOLD}$HOSTNAME${NC}"
if $ENCRYPT; then
echo -e "  Criptogr. : ${BOLD}LUKS2 + LVM (AES-256-XTS, Argon2id)${NC}"
fi
echo ""
echo -e "${YELLOW}  Remova a mídia de instalação e reinicie:${NC}"
echo -e "  ${BOLD}reboot${NC}"
echo ""
