#!/bin/bash
# =============================================================================
#  Void Linux Installer - GRUB + ext4 + LVM sobre LUKS
#  Suporte a XFCE4 ou MATE + LightDM
#  Uso: boot pelo live ISO do Void, execute como root
# =============================================================================
# Script criando para aprendizado do void linux
set -euo pipefail

# ── Cores ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()   { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()   { echo -e "${YELLOW}[AVISO]${NC} $*"; }
error()  { echo -e "${RED}[ERRO]${NC}  $*"; exit 1; }
header() {
    echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"
}

# ── Verificação inicial ────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Execute como root (sudo ou su -)"
command -v xbps-install &>/dev/null || error "Este script deve rodar dentro do live ISO do Void Linux"

# ── Instalar dependências no live ISO ─────────────────────────────────────────
header "VERIFICANDO DEPENDÊNCIAS"
info "Instalando ferramentas necessárias..."
xbps-install -Sy gptfdisk cryptsetup lvm2 parted || error "Falha ao instalar dependências"
command -v sgdisk   &>/dev/null || error "sgdisk não encontrado"
command -v partprobe &>/dev/null || error "partprobe não encontrado"
ok "Dependências prontas"

# ── Detectar modo de boot ──────────────────────────────────────────────────────
if [[ -d /sys/firmware/efi/efivars ]]; then
    BOOT_MODE="uefi"
    info "Modo de boot: UEFI"
else
    BOOT_MODE="bios"
    info "Modo de boot: BIOS/Legacy"
fi

# =============================================================================
#  ETAPA 1 — Escolha do disco
# =============================================================================
header "DISCOS DISPONÍVEIS"

lsblk -d -o NAME,SIZE,MODEL,TYPE | grep -E "^(sd|vd|nvme|mmcblk)" || true
echo ""
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -v "loop"
echo ""

while true; do
    read -rp "$(echo -e "${BOLD}Digite o disco alvo (ex: sda, vda, nvme0n1): ${NC}")" DISK_NAME
    DISK="/dev/${DISK_NAME}"
    [[ -b "$DISK" ]] && break
    warn "Dispositivo '$DISK' não encontrado. Tente novamente."
done

ok "Disco selecionado: $DISK"
warn "TODO O CONTEÚDO DE $DISK SERÁ APAGADO!"
read -rp "Tem certeza? Digite 'SIM' para continuar: " CONFIRM
[[ "$CONFIRM" != "SIM" ]] && error "Instalação cancelada."

# =============================================================================
#  ETAPA 2 — Criptografia?
# =============================================================================
header "CRIPTOGRAFIA"

ENCRYPT=false
read -rp "$(echo -e "${BOLD}Deseja usar criptografia LUKS+LVM? [s/N]: ${NC}")" USE_CRYPT
if [[ "$USE_CRYPT" =~ ^[Ss]$ ]]; then
    ENCRYPT=true
    ok "Criptografia LUKS+LVM ativada"
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
        1) DE="xfce4"; break ;;
        2) DE="mate";  break ;;
        *) warn "Opção inválida." ;;
    esac
done
ok "Desktop selecionado: $DE com LightDM"

# =============================================================================
#  ETAPA 4 — Dados do sistema
# =============================================================================
header "CONFIGURAÇÃO DO SISTEMA"

read -rp "$(echo -e "${BOLD}Hostname [voidlinux]: ${NC}")" HOSTNAME
[[ -z "$HOSTNAME" ]] && HOSTNAME="voidlinux"

read -rp "$(echo -e "${BOLD}Nome do usuário [user]: ${NC}")" USERNAME
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

read -rp "$(echo -e "${BOLD}Fuso horário [America/Sao_Paulo]: ${NC}")" TIMEZONE
[[ -z "$TIMEZONE" ]] && TIMEZONE="America/Sao_Paulo"

read -rp "$(echo -e "${BOLD}Locale [pt_BR.UTF-8]: ${NC}")" LOCALE
[[ -z "$LOCALE" ]] && LOCALE="pt_BR.UTF-8"

# =============================================================================
#  ETAPA 5 — Resumo e confirmação final
# =============================================================================
header "RESUMO DA INSTALAÇÃO"

echo -e "  Disco alvo   : ${BOLD}$DISK${NC}"
echo -e "  Modo boot    : ${BOLD}${BOOT_MODE^^}${NC}"
if $ENCRYPT; then
    echo -e "  Criptografia : ${BOLD}SIM (LUKS+LVM)${NC}"
else
    echo -e "  Criptografia : ${BOLD}NÃO${NC}"
fi
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
#  ETAPA 6 — Desmontar e particionar
# =============================================================================
header "PARTICIONANDO $DISK"

info "Desmontando partições em uso (se houver)..."
swapoff -a 2>/dev/null || true
for mp in $(lsblk -lno MOUNTPOINT "$DISK" 2>/dev/null | grep -v "^$" | sort -r); do
    umount -lf "$mp" 2>/dev/null && info "Desmontado: $mp" || true
done
dmsetup remove_all 2>/dev/null || true
vgchange -an 2>/dev/null || true
sleep 1

# Zerar assinaturas antigas
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
partprobe "$DISK"
sleep 1

# Sufixo de partição (nvme/mmcblk usam 'p')
if [[ "$DISK_NAME" == nvme* ]] || [[ "$DISK_NAME" == mmcblk* ]]; then
    P="p"
else
    P=""
fi

if [[ "$BOOT_MODE" == "uefi" ]]; then
    info "Criando partições GPT (UEFI)"
    sgdisk -n 1:0:+512M  -t 1:ef00 -c 1:"EFI"  "$DISK"
    sgdisk -n 2:0:+1G    -t 2:8300 -c 2:"boot" "$DISK"
    sgdisk -n 3:0:0      -t 3:8300 -c 3:"root" "$DISK"
    PART_EFI="${DISK}${P}1"
    PART_BOOT="${DISK}${P}2"
    PART_ROOT="${DISK}${P}3"
else
    info "Criando partições GPT/BIOS (Legacy)"
    sgdisk -n 1:0:+1M    -t 1:ef02 -c 1:"bios" "$DISK"
    sgdisk -n 2:0:+512M  -t 2:8300 -c 2:"boot" "$DISK"
    sgdisk -n 3:0:0      -t 3:8300 -c 3:"root" "$DISK"
    PART_BOOT="${DISK}${P}2"
    PART_ROOT="${DISK}${P}3"
fi

partprobe "$DISK"
sleep 2

if [[ "$BOOT_MODE" == "uefi" ]]; then
    mkfs.fat -F32 -n EFI "$PART_EFI"
    ok "Partição EFI formatada"
fi

mkfs.ext4 -F -L boot "$PART_BOOT"
ok "Partição /boot formatada (ext4)"

# =============================================================================
#  ETAPA 7 — LUKS + LVM
# =============================================================================
if $ENCRYPT; then
    header "CONFIGURANDO LUKS + LVM"

    info "Formatando container LUKS2..."
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

    pvcreate "$LVM_DEV"
    vgcreate vgvoid "$LVM_DEV"
    lvcreate -l 100%FREE vgvoid -n root

    PART_REALROOT="/dev/vgvoid/root"
    ok "LVM configurado: /dev/vgvoid/root"
else
    PART_REALROOT="$PART_ROOT"
    LUKS_UUID=""
fi

# =============================================================================
#  ETAPA 8 — Formatar raiz e montar
# =============================================================================
header "FORMATANDO E MONTANDO"

mkfs.ext4 -F -L void-root "$PART_REALROOT"
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
#  ETAPA 9 — Instalação dos pacotes
# =============================================================================
header "INSTALANDO SISTEMA BASE"

MIRROR="https://repo-default.voidlinux.org/current"
XBPS_ARCH=$(xbps-uhelper arch)
info "Arquitetura: $XBPS_ARCH"

BASE_PKGS=(
    base-system
    grub
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

# grub-x86_64-efi somente em UEFI (evita elemento vazio no array)
if [[ "$BOOT_MODE" == "uefi" ]]; then
    BASE_PKGS+=(grub-x86_64-efi)
fi

if [[ "$DE" == "xfce4" ]]; then
    # xfce4 meta-pacote já inclui: Thunar, ristretto, mousepad, xfce4-terminal, etc.
    DE_PKGS=(
        xfce4
        xfce4-screenshooter
        xfce4-notifyd
        xfce4-pulseaudio-plugin
        thunar-archive-plugin
        xarchiver
        pavucontrol
        gvfs
        pulseaudio
        tumbler
    )
else
    # mate meta-pacote já inclui a maioria dos apps
    DE_PKGS=(
        mate
        mate-extra
        mate-terminal
        pavucontrol
        gvfs
        pulseaudio
    )
fi

ALL_PKGS=("${BASE_PKGS[@]}" "${DE_PKGS[@]}")

info "Instalando pacotes (pode demorar alguns minutos)..."
XBPS_ARCH="$XBPS_ARCH" xbps-install \
    -S \
    -R "$MIRROR" \
    -r /mnt \
    "${ALL_PKGS[@]}" || error "Falha na instalação dos pacotes"

ok "Pacotes instalados com sucesso"

# =============================================================================
#  ETAPA 10 — Configuração base
# =============================================================================
header "CONFIGURANDO O SISTEMA"

BOOT_UUID=$(blkid -s UUID -o value "$PART_BOOT")
ROOT_UUID=$(blkid -s UUID -o value "$PART_REALROOT")

{
    echo "# /etc/fstab gerado pelo void-install.sh"
    if [[ "$BOOT_MODE" == "uefi" ]]; then
        EFI_UUID=$(blkid -s UUID -o value "$PART_EFI")
        echo "UUID=$EFI_UUID  /boot/efi  vfat  defaults  0 2"
    fi
    echo "UUID=$BOOT_UUID  /boot  ext4  defaults  0 2"
    echo "UUID=$ROOT_UUID  /      ext4  defaults  0 1"
    echo "tmpfs  /tmp  tmpfs  defaults,nosuid,nodev  0 0"
} > /mnt/etc/fstab

echo "$HOSTNAME" > /mnt/etc/hostname
echo "LANG=$LOCALE" > /mnt/etc/locale.conf
echo "$LOCALE UTF-8" >> /mnt/etc/default/libc-locales
ln -sf "/usr/share/zoneinfo/$TIMEZONE" /mnt/etc/localtime

cat > /mnt/etc/rc.conf <<EOF
TIMEZONE="$TIMEZONE"
KEYMAP="br-abnt2"
FONT="Lat2-Terminus16"
HARDWARECLOCK="UTC"
EOF

cat > /mnt/etc/hosts <<EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
EOF

if $ENCRYPT; then
    echo "cryptlvm  UUID=$LUKS_UUID  none  luks" > /mnt/etc/crypttab
    ok "/etc/crypttab configurado"
fi

ok "Configurações básicas aplicadas"

# =============================================================================
#  ETAPA 11 — Chroot
# =============================================================================
header "CONFIGURANDO DENTRO DO CHROOT"

mount --rbind /sys  /mnt/sys;  mount --make-rslave /mnt/sys
mount --rbind /dev  /mnt/dev;  mount --make-rslave /mnt/dev
mount --rbind /proc /mnt/proc; mount --make-rslave /mnt/proc
cp /etc/resolv.conf /mnt/etc/resolv.conf

# Exportar variáveis para uso dentro do heredoc do chroot
_USERNAME="$USERNAME"
_USER_PASS="$USER_PASS"
_ROOT_PASS="$ROOT_PASS"
_DE="$DE"
_BOOT_MODE="$BOOT_MODE"
_ENCRYPT="$ENCRYPT"
_LUKS_UUID="$LUKS_UUID"
_DISK="$DISK"

chroot /mnt /bin/bash -s "$_USERNAME" "$_USER_PASS" "$_ROOT_PASS" \
    "$_DE" "$_BOOT_MODE" "$_ENCRYPT" "$_LUKS_UUID" "$_DISK" <<'CHROOT_EOF'

USERNAME="$1"
USER_PASS="$2"
ROOT_PASS="$3"
DE="$4"
BOOT_MODE="$5"
ENCRYPT="$6"
LUKS_UUID="$7"
DISK="$8"

set -euo pipefail

xbps-reconfigure -f glibc-locales

# Definir senhas via openssl (funciona sempre no chroot do Void)
ROOT_HASH=$(openssl passwd -6 "${ROOT_PASS}")
USER_HASH=$(openssl passwd -6 "${USER_PASS}")
usermod -p "${ROOT_HASH}" root
useradd -m -G wheel,audio,video,optical,storage,network,plugdev -s /bin/bash "${USERNAME}"
usermod -p "${USER_HASH}" "${USERNAME}"

echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

for svc in dbus elogind NetworkManager lightdm; do
    ln -sf /etc/sv/$svc /etc/runit/runsvdir/default/ 2>/dev/null || true
done

mkdir -p /etc/lightdm
LIGHTDM_CFG="/etc/lightdm/lightdm.conf"
if grep -q "^\[Seat:\*\]" "$LIGHTDM_CFG" 2>/dev/null; then
    # xfce4 no LightDM se chama "xfce", não "xfce4"
    SESSION_NAME="${DE}"
    [[ "$DE" == "xfce4" ]] && SESSION_NAME="xfce"
    sed -i "s|^#*user-session=.*|user-session=${SESSION_NAME}|" "$LIGHTDM_CFG"
else
    SESSION_NAME="${DE}"
    [[ "$DE" == "xfce4" ]] && SESSION_NAME="xfce"
    printf '\n[Seat:*]\nuser-session=%s\n' "${SESSION_NAME}" >> "$LIGHTDM_CFG"
fi

mkdir -p /etc/dracut.conf.d
cat > /etc/dracut.conf.d/void.conf <<DRACUT
hostonly=yes
hostonly_cmdline=yes
add_dracutmodules+=" crypt dm lvm resume "
omit_dracutmodules+=" network "
DRACUT

if [[ "$ENCRYPT" == "true" ]]; then
    mkdir -p /etc/kernel
    echo "rd.luks.uuid=${LUKS_UUID} rd.lvm.vg=vgvoid root=/dev/vgvoid/root" \
        > /etc/kernel/cmdline
fi

KVER=$(ls /lib/modules | sort -V | tail -1)
dracut --force --kver "$KVER"

if [[ "$BOOT_MODE" == "uefi" ]]; then
    grub-install --target=x86_64-efi \
        --efi-directory=/boot/efi \
        --bootloader-id=VOID \
        --recheck
else
    grub-install --target=i386-pc --recheck "${DISK}"
fi

if [[ "$ENCRYPT" == "true" ]]; then
    sed -i "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"rd.luks.uuid=${LUKS_UUID} rd.lvm.vg=vgvoid root=/dev/vgvoid/root\"|" \
        /etc/default/grub
    echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub
fi

sed -i 's/^#*GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
update-grub

echo "[chroot] Concluído com sucesso"
CHROOT_EOF

ok "Chroot concluído"

# =============================================================================
#  ETAPA 12 — Finalização
# =============================================================================
header "FINALIZANDO"

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
