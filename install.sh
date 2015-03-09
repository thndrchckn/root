#!/usr/bin/env bash
set -ex -o pipefail -o nounset

# Raw Partitioning

parted --script --align optimal -- /dev/sda mklabel gpt

parted --script --align optimal -- /dev/sda mkpart primary 2 4
parted --script --align optimal -- /dev/sda name 1 bios_grub
parted --script --align optimal -- /dev/sda set 1 bios_grub on

parted --script --align optimal -- /dev/sda mkpart primary 4 204
parted --script --align optimal -- /dev/sda name 2 boot
parted --script --align optimal -- /dev/sda set 2 boot on

parted --script --align optimal -- /dev/sda mkpart primary 204 -1
parted --script --align optimal -- /dev/sda name 3 lvm
parted --script --align optimal -- /dev/sda set 3 lvm on

# LVM Partitioning

pvcreate -ff --yes /dev/sda3
vgcreate LvmDvc /dev/sda3
lvcreate --zero y --wipesignatures y --name root --size 2G LvmDvc
lvcreate --zero y --wipesignatures y --name home --size 2G LvmDvc
lvcreate --zero y --wipesignatures y --name var --size 1G LvmDvc
lvcreate --zero y --wipesignatures y --name usr --size 1G LvmDvc
lvcreate --zero y --wipesignatures y --name swap --size 4G LvmDvc

# Root Partition

echo asdfasdf | cryptsetup -q --key-file - luksFormat /dev/mapper/LvmDvc-root
echo asdfasdf | cryptsetup -q --key-file - luksOpen /dev/mapper/LvmDvc-root LuksDvc-root
mkfs.ext4 -q /dev/mapper/LuksDvc-root

mkdir -p /mnt/archbox
mount /dev/mapper/LuksDvc-root /mnt/archbox

# Boot Partition

mkfs.ext4 -q /dev/sda2

# Encrypted Partitions

mkdir -p /mnt/archbox/etc/cryptkeys
chmod 400 /mnt/archbox/etc/cryptkeys

dd if=/dev/random of=/mnt/archbox/etc/cryptkeys/home bs=512 count=4 iflag=fullblock
chmod 400 /mnt/archbox/etc/cryptkeys/home
cryptsetup -q --key-file /mnt/archbox/etc/cryptkeys/home luksFormat /dev/mapper/LvmDvc-home
cryptsetup -q --key-file /mnt/archbox/etc/cryptkeys/home luksOpen /dev/mapper/LvmDvc-home LuksDvc-home
mkfs.ext4 -q /dev/mapper/LuksDvc-home

dd if=/dev/random of=/mnt/archbox/etc/cryptkeys/var bs=512 count=4 iflag=fullblock
chmod 400 /mnt/archbox/etc/cryptkeys/var
cryptsetup -q --key-file /mnt/archbox/etc/cryptkeys/var luksFormat /dev/mapper/LvmDvc-var
cryptsetup -q --key-file /mnt/archbox/etc/cryptkeys/var luksOpen /dev/mapper/LvmDvc-var LuksDvc-var
mkfs.ext4 -q /dev/mapper/LuksDvc-var

dd if=/dev/random of=/mnt/archbox/etc/cryptkeys/usr bs=512 count=4 iflag=fullblock
chmod 400 /mnt/archbox/etc/cryptkeys/usr
cryptsetup -q --key-file /mnt/archbox/etc/cryptkeys/usr luksFormat /dev/mapper/LvmDvc-usr
cryptsetup -q --key-file /mnt/archbox/etc/cryptkeys/usr luksOpen /dev/mapper/LvmDvc-usr LuksDvc-usr
mkfs.ext4 -q /dev/mapper/LuksDvc-usr

dd if=/dev/random of=/mnt/archbox/etc/cryptkeys/swap bs=512 count=4 iflag=fullblock
chmod 400 /mnt/archbox/etc/cryptkeys/swap
cryptsetup -q --key-file /mnt/archbox/etc/cryptkeys/swap luksFormat /dev/mapper/LvmDvc-swap
cryptsetup -q --key-file /mnt/archbox/etc/cryptkeys/swap luksOpen /dev/mapper/LvmDvc-swap LuksDvc-swap
mkswap /dev/mapper/LuksDvc-swap

# Mount

mkdir -p /mnt/archbox/boot
mount /dev/sda2 /mnt/archbox/boot

mkdir -p /mnt/archbox/home
mount /dev/mapper/LuksDvc-home /mnt/archbox/home

mkdir -p /mnt/archbox/var
mount /dev/mapper/LuksDvc-var /mnt/archbox/var

mkdir -p /mnt/archbox/usr
mount /dev/mapper/LuksDvc-usr /mnt/archbox/usr

swapon /dev/mapper/LuksDvc-swap

# Packages

mkdir -p ./cache-dir
rm -f /mnt/archbox/var/lib/pacman/db.lck
pacstrap /mnt/archbox --cachedir ./cache-dir base grub

# Root password

echo "root:asdfasdf" | chpasswd --root /mnt/archbox

# FSTab

genfstab -U -p /mnt/archbox >> /mnt/archbox/etc/fstab

# CryptTab

echo "" > /mnt/archbox/etc/crypttab
echo "home /dev/mapper/LvmDvc-home /mnt/archbox/etc/cryptkeys/home" >> /mnt/archbox/etc/crypttab
echo "usr /dev/mapper/LvmDvc-usr /mnt/archbox/etc/cryptkeys/usr" >> /mnt/archbox/etc/crypttab
echo "var /dev/mapper/LvmDvc-var /mnt/archbox/etc/cryptkeys/var" >> /mnt/archbox/etc/crypttab
echo "swap /dev/mapper/LvmDvc-swap /mnt/archbox/etc/cryptkeys/swap" >> /mnt/archbox/etc/crypttab

# Ramdisk

file=/mnt/archbox/etc/mkinitcpio.conf

search="^\s*MODULES=.*$"
replace="MODULES=\\\"virtio virtio_blk virtio_pci virtio_net\\\""
grep -q "$search" "$file" && sed -i "s#$search#$replace#" "$file" || echo "$replace" >> "$file"

search="^\s*HOOKS=.*$"
replace="HOOKS=\\\"base udev autodetect modconf block keymap encrypt lvm2 filesystems keyboard shutdown fsck usr\\\""
grep -q "$search" "$file" && sed -i "s#$search#$replace#" "$file" || echo "$replace" >> "$file"

arch-chroot /mnt/archbox mkinitcpio -p linux

# Bootloader

arch-chroot /mnt/archbox grub-install --target=i386-pc --recheck /dev/sda

file=/mnt/archbox/etc/default/grub

search="^\s*GRUB_CMDLINE_LINUX=.*$"
replace="GRUB_CMDLINE_LINUX=\\\"init=/usr/lib/systemd/systemd cryptdevice=/dev/mapper/LvmDvc-root:LuksDvc-root root=/dev/mapper/LuksDvc-root quiet\\\""
grep -q "$search" "$file" && sed -i "s#$search#$replace#" "$file" || echo "$replace" >> "$file"

search="^\s*GRUB_DISABLE_LINUX_UUID=.*$"
replace="GRUB_DISABLE_LINUX_UUID=true"
grep -q "$search" "$file" && sed -i "s#$search#$replace#" "$file" || echo "$replace" >> "$file"

arch-chroot /mnt/archbox grub-mkconfig -o /boot/grub/grub.cfg
