#!/bin/bash
# =============================================================================
#  Void Linux Installer - Seguindo documentação oficial do Void Linux
#  GRUB + LUKS1 + LVM + ext4 + XFCE4 ou MATE + LightDM
#  Referência: https://docs.voidlinux.org/installation/full-disk-encryption.html
#  Uso: boot pelo live ISO do Void, execute como root
# =============================================================================

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
xbps-install -Sy gptfdisk cryptsetup lvm2 parted xtools || error "Falha ao instalar dependências"
command -v sgdisk    &>/dev/null || error "sgdisk não encontrado"
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

# Sufixo de partição (nvme/mmcblk usam 'p')
if [[ "$DISK_NAME" == nvme* ]] || [[ "$DISK_NAME" == mmcblk* ]]; then
    P="p"
else
    P=""
fi

# =============================================================================
#  ETAPA 2 — Criptografia?
# =============================================================================
header "CRIPTOGRAFIA"

ENCRYPT=false
read -rp "$(echo -e "${BOLD}Deseja usar criptografia LUKS? [s/N]: ${NC}")" USE_CRYPT
if [[ "$USE_CRYPT" =~ ^[Ss]$ ]]; then
    ENCRYPT=true
    ok "Criptografia LUKS1 ativada (compatível com GRUB)"
else
    info "Instalação sem criptografia"
fi

# =============================================================================
#  ETAPA 3 — Particionamento LVM
# =============================================================================
header "ESQUEMA DE PARTICIONAMENTO"

echo "  1) Somente /          (tudo em uma partição)"
echo "  2) / + swap"
echo "  3) / + swap + /home   (recomendado)"
echo ""
while true; do
    read -rp "$(echo -e "${BOLD}Escolha [1/2/3]: ${NC}")" LVM_CHOICE
    case "$LVM_CHOICE" in
        1) LVM_SCHEME="root_only"; break ;;
        2) LVM_SCHEME="root_swap"; break ;;
        3) LVM_SCHEME="root_swap_home"; break ;;
        *) warn "Opção inválida." ;;
    esac
done

if [[ "$LVM_SCHEME" == "root_swap" ]] || [[ "$LVM_SCHEME" == "root_swap_home" ]]; then
    read -rp "$(echo -e "${BOLD}Tamanho do swap (ex: 2G, 4G) [2G]: ${NC}")" SWAP_SIZE
    [[ -z "$SWAP_SIZE" ]] && SWAP_SIZE="2G"
fi

if [[ "$LVM_SCHEME" == "root_swap_home" ]]; then
    read -rp "$(echo -e "${BOLD}Tamanho do / raiz (ex: 20G, 30G) [20G]: ${NC}")" ROOT_SIZE
    [[ -z "$ROOT_SIZE" ]] && ROOT_SIZE="20G"
fi

# =============================================================================
#  ETAPA 4 — Desktop Environment
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
#  ETAPA 5 — Dados do sistema
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
#  ETAPA 6 — Resumo e confirmação final
# =============================================================================
header "RESUMO DA INSTALAÇÃO"

echo -e "  Disco alvo   : ${BOLD}$DISK${NC}"
echo -e "  Modo boot    : ${BOLD}${BOOT_MODE^^}${NC}"
if $ENCRYPT; then
    echo -e "  Criptografia : ${BOLD}SIM (LUKS1 — compatível com GRUB)${NC}"
else
    echo -e "  Criptografia : ${BOLD}NÃO${NC}"
fi
echo -e "  LVM          : ${BOLD}$LVM_SCHEME${NC}"
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
#  ETAPA 7 — Particionamento do disco
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

wipefs -af "$DISK"
sgdisk --zap-all "$DISK"
partprobe "$DISK"
sleep 1

if [[ "$BOOT_MODE" == "uefi" ]]; then
    info "Criando tabela GPT (UEFI)"
    # Partição EFI + partição LUKS/raiz
    sgdisk -n 1:0:+128M -t 1:ef00 -c 1:"EFI"  "$DISK"
    sgdisk -n 2:0:0     -t 2:8300 -c 2:"root" "$DISK"
    PART_EFI="${DISK}${P}1"
    PART_LUKS="${DISK}${P}2"
else
    info "Criando tabela MBR (BIOS/Legacy)"
    # Seguindo documentação: uma partição bootável
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary 1MiB 100%
    parted -s "$DISK" set 1 boot on
    PART_LUKS="${DISK}${P}1"
fi

partprobe "$DISK"
sleep 2

if [[ "$BOOT_MODE" == "uefi" ]]; then
    mkfs.fat -F32 -n EFI "$PART_EFI"
    ok "Partição EFI formatada"
fi

ok "Disco particionado"

# =============================================================================
#  ETAPA 8 — LUKS1 + LVM (seguindo documentação oficial)
# =============================================================================
if $ENCRYPT; then
    header "CONFIGURANDO LUKS1 + LVM"

    # Documentação oficial usa LUKS1 — compatível com GRUB sem configuração extra
    info "Formatando container LUKS1..."
    echo -n "$LUKS_PASS" | cryptsetup luksFormat \
        --type luks1 \
        "$PART_LUKS" -

    info "Abrindo container LUKS..."
    echo -n "$LUKS_PASS" | cryptsetup luksOpen "$PART_LUKS" voidvm -

    LUKS_UUID=$(blkid -s UUID -o value "$PART_LUKS")
    LVM_DEV="/dev/mapper/voidvm"

    info "Criando LVM..."
    pvcreate "$LVM_DEV"
    vgcreate voidvm "$LVM_DEV"

    case "$LVM_SCHEME" in
        root_only)
            lvcreate --name root -l 100%FREE voidvm
            ;;
        root_swap)
            lvcreate --name swap -L "$SWAP_SIZE" voidvm
            lvcreate --name root -l 100%FREE voidvm
            ;;
        root_swap_home)
            lvcreate --name root -L "$ROOT_SIZE" voidvm
            lvcreate --name swap -L "$SWAP_SIZE" voidvm
            lvcreate --name home -l 100%FREE voidvm
            ;;
    esac

    ok "LVM configurado"
    PART_ROOT="/dev/voidvm/root"
    PART_SWAP="/dev/voidvm/swap"
    PART_HOME="/dev/voidvm/home"

else
    # Sem criptografia — LVM direto sobre a partição
    info "Criando LVM direto..."
    pvcreate "$PART_LUKS"
    vgcreate voidvm "$PART_LUKS"

    case "$LVM_SCHEME" in
        root_only)
            lvcreate --name root -l 100%FREE voidvm
            ;;
        root_swap)
            lvcreate --name swap -L "$SWAP_SIZE" voidvm
            lvcreate --name root -l 100%FREE voidvm
            ;;
        root_swap_home)
            lvcreate --name root -L "$ROOT_SIZE" voidvm
            lvcreate --name swap -L "$SWAP_SIZE" voidvm
            lvcreate --name home -l 100%FREE voidvm
            ;;
    esac

    LUKS_UUID=""
    PART_ROOT="/dev/voidvm/root"
    PART_SWAP="/dev/voidvm/swap"
    PART_HOME="/dev/voidvm/home"
fi

# =============================================================================
#  ETAPA 9 — Formatar e montar
# =============================================================================
header "FORMATANDO E MONTANDO"

mkfs.ext4 -F -L void-root "$PART_ROOT"
ok "/ formatado (ext4)"

if [[ "$LVM_SCHEME" == "root_swap" ]] || [[ "$LVM_SCHEME" == "root_swap_home" ]]; then
    mkswap "$PART_SWAP"
    swapon "$PART_SWAP"
    ok "swap ativado"
fi

if [[ "$LVM_SCHEME" == "root_swap_home" ]]; then
    mkfs.ext4 -F -L void-home "$PART_HOME"
    ok "/home formatado (ext4)"
fi

# Montar
mount "$PART_ROOT" /mnt

if [[ "$LVM_SCHEME" == "root_swap_home" ]]; then
    mkdir -p /mnt/home
    mount "$PART_HOME" /mnt/home
fi

if [[ "$BOOT_MODE" == "uefi" ]]; then
    mkdir -p /mnt/boot/efi
    mount "$PART_EFI" /mnt/boot/efi
fi

ok "Sistemas de arquivos montados"

# =============================================================================
#  ETAPA 10 — Copiar chaves RSA do live ISO (documentação oficial)
# =============================================================================
info "Copiando chaves RSA do repositório..."
mkdir -p /mnt/var/db/xbps/keys
cp /var/db/xbps/keys/* /mnt/var/db/xbps/keys/
ok "Chaves RSA copiadas (sem prompt durante instalação)"

# =============================================================================
#  ETAPA 11 — Instalação dos pacotes via XBPS
# =============================================================================
header "INSTALANDO SISTEMA BASE"

MIRROR="https://repo-default.voidlinux.org/current"
XBPS_ARCH=$(xbps-uhelper arch)
info "Arquitetura: $XBPS_ARCH"

# Pacotes base conforme documentação oficial
BASE_PKGS=(
    base-system
    lvm2
    cryptsetup
    grub
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

# GRUB EFI apenas se UEFI
if [[ "$BOOT_MODE" == "uefi" ]]; then
    BASE_PKGS+=(grub-x86_64-efi)
fi

# Pacotes do DE
if [[ "$DE" == "xfce4" ]]; then
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
    -Sy \
    -R "$MIRROR" \
    -r /mnt \
    "${ALL_PKGS[@]}" || error "Falha na instalação dos pacotes"

ok "Pacotes instalados com sucesso"

# =============================================================================
#  ETAPA 12 — Gerar fstab com xgenfstab (documentação oficial)
# =============================================================================
header "GERANDO FSTAB"

# Documentação oficial usa xgenfstab do xtools
xgenfstab /mnt > /mnt/etc/fstab
ok "/etc/fstab gerado via xgenfstab"
cat /mnt/etc/fstab

# =============================================================================
#  ETAPA 13 — Configurações base fora do chroot
# =============================================================================
header "CONFIGURANDO O SISTEMA"

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

ok "Configurações básicas aplicadas"

# =============================================================================
#  ETAPA 14 — Chroot (usando xchroot do xtools, como na documentação)
# =============================================================================
header "CONFIGURANDO DENTRO DO CHROOT"

mount --rbind /sys  /mnt/sys;  mount --make-rslave /mnt/sys
mount --rbind /dev  /mnt/dev;  mount --make-rslave /mnt/dev
mount --rbind /proc /mnt/proc; mount --make-rslave /mnt/proc
cp /etc/resolv.conf /mnt/etc/resolv.conf

# Passar variáveis para o chroot via argumentos posicionais
chroot /mnt /bin/bash -s \
    "$USERNAME" "$USER_PASS" "$ROOT_PASS" \
    "$DE" "$BOOT_MODE" "$ENCRYPT" \
    "${LUKS_UUID:-}" "$DISK" "$LVM_SCHEME" \
    "${SWAP_SIZE:-}" "$LOCALE" <<'CHROOT_EOF'

USERNAME="$1"
USER_PASS="$2"
ROOT_PASS="$3"
DE="$4"
BOOT_MODE="$5"
ENCRYPT="$6"
LUKS_UUID="$7"
DISK="$8"
LVM_SCHEME="$9"
SWAP_SIZE="${10}"
LOCALE="${11}"

set -euo pipefail

# Permissões corretas (documentação oficial)
chown root:root /
chmod 755 /

# Locale
xbps-reconfigure -f glibc-locales

# Senhas via openssl (confiável no chroot)
ROOT_HASH=$(openssl passwd -6 "${ROOT_PASS}")
USER_HASH=$(openssl passwd -6 "${USER_PASS}")
usermod -p "${ROOT_HASH}" root
useradd -m -G wheel,audio,video,optical,storage,network,plugdev -s /bin/bash "${USERNAME}"
usermod -p "${USER_HASH}" "${USERNAME}"

echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# Serviços runit
for svc in dbus elogind NetworkManager lightdm; do
    ln -sf /etc/sv/$svc /etc/runit/runsvdir/default/ 2>/dev/null || true
done

# Sessão LightDM (xfce4 -> xfce no lightdm)
mkdir -p /etc/lightdm
LIGHTDM_CFG="/etc/lightdm/lightdm.conf"
SESSION_NAME="$DE"
[[ "$DE" == "xfce4" ]] && SESSION_NAME="xfce"
if grep -q "^\[Seat:\*\]" "$LIGHTDM_CFG" 2>/dev/null; then
    sed -i "s|^#*user-session=.*|user-session=${SESSION_NAME}|" "$LIGHTDM_CFG"
else
    printf '\n[Seat:*]\nuser-session=%s\n' "${SESSION_NAME}" >> "$LIGHTDM_CFG"
fi

# ── GRUB com LUKS ─────────────────────────────────────────────────────────────
if [[ "$ENCRYPT" == "true" ]]; then
    # Documentação oficial: GRUB_ENABLE_CRYPTODISK=y
    echo 'GRUB_ENABLE_CRYPTODISK=y' >> /etc/default/grub

    # rd.lvm.vg + rd.luks.uuid no cmdline
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=4 rd.lvm.vg=voidvm rd.luks.uuid=${LUKS_UUID}\"|" \
        /etc/default/grub

    # ── Keyfile para não digitar senha 2x (documentação oficial) ──────────────
    info_chroot() { echo "[chroot] $*"; }
    info_chroot "Gerando keyfile LUKS..."
    dd bs=1 count=64 if=/dev/urandom of=/boot/volume.key 2>/dev/null
    chmod 000 /boot/volume.key
    chmod -R g-rwx,o-rwx /boot

    # Adicionar keyfile ao LUKS (precisa da senha)
    # Será feito fora do chroot pois precisa do dispositivo físico

    # crypttab com keyfile
    echo "voidvm   /dev/disk/by-uuid/${LUKS_UUID}   /boot/volume.key   luks" \
        > /etc/crypttab

    # dracut para incluir keyfile e crypttab no initramfs
    mkdir -p /etc/dracut.conf.d
    cat > /etc/dracut.conf.d/10-crypt.conf <<DRACUT
add_dracutmodules+=" crypt dm lvm "
install_items+=" /boot/volume.key /etc/crypttab "
DRACUT
fi

sed -i 's/^#*GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub

# ── Instalar GRUB ─────────────────────────────────────────────────────────────
if [[ "$BOOT_MODE" == "uefi" ]]; then
    grub-install --target=x86_64-efi \
        --efi-directory=/boot/efi \
        --bootloader-id=VOID \
        --recheck
else
    # Documentação oficial: grub-install /dev/sda (simples)
    grub-install "$DISK"
fi

# ── Gerar initramfs e reconfigurar todos os pacotes (documentação oficial) ────
xbps-reconfigure -fa

echo "[chroot] Concluído com sucesso"
CHROOT_EOF

ok "Chroot concluído"

# =============================================================================
#  ETAPA 15 — Adicionar keyfile ao LUKS (fora do chroot, acessa dispositivo)
# =============================================================================
if $ENCRYPT; then
    header "CONFIGURANDO KEYFILE LUKS"
    info "Adicionando keyfile ao container LUKS (digite a senha LUKS quando solicitado)..."
    cryptsetup luksAddKey "$PART_LUKS" /mnt/boot/volume.key
    ok "Keyfile adicionado — sistema não pedirá senha duas vezes no boot"
fi

# =============================================================================
#  ETAPA 16 — Finalização
# =============================================================================
header "FINALIZANDO"

umount -R /mnt 2>/dev/null || true

if $ENCRYPT; then
    vgchange -an voidvm 2>/dev/null || true
    cryptsetup close voidvm 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║   INSTALAÇÃO CONCLUÍDA COM SUCESSO! 🎉  ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Desktop      : ${BOLD}${DE^^}${NC}"
echo -e "  Usuário      : ${BOLD}$USERNAME${NC}"
echo -e "  Hostname     : ${BOLD}$HOSTNAME${NC}"
echo -e "  LVM          : ${BOLD}$LVM_SCHEME${NC}"
if $ENCRYPT; then
    echo -e "  Criptografia : ${BOLD}LUKS1 (compatível com GRUB)${NC}"
    echo -e "  Keyfile      : ${BOLD}/boot/volume.key (sem dupla senha no boot)${NC}"
fi
echo ""
echo -e "${YELLOW}  Remova a mídia de instalação e reinicie:${NC}"
echo -e "  ${BOLD}reboot${NC}"
echo ""
