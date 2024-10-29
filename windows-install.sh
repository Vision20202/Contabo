#!/bin/bash

# Обновление системы
apt update -y && apt upgrade -y

# Установка необходимых пакетов
apt install grub2 wimtools ntfs-3g -y

# Получаем размер диска в GB и конвертируем в MB
disk_size_gb=$(parted /dev/sda --script print | awk '/^Disk \/dev\/sda:/ {print int($3)}')
disk_size_mb=$((disk_size_gb * 1024))

# Рассчитываем размер раздела (25% от общего размера)
part_size_mb=$((disk_size_mb / 4))

# Создаем GPT таблицу разделов
parted /dev/sda --script -- mklabel gpt

# Создаем два раздела
parted /dev/sda --script -- mkpart primary ntfs 1MB ${part_size_mb}MB
parted /dev/sda --script -- mkpart primary ntfs ${part_size_mb}MB $((2 * part_size_mb))MB

# Сообщаем ядру о изменениях в таблице разделов
partprobe /dev/sda
sleep 30
partprobe /dev/sda
sleep 30
partprobe /dev/sda
sleep 30 

# Форматируем разделы
mkfs.ntfs -f /dev/sda1
mkfs.ntfs -f /dev/sda2

echo "NTFS разделы созданы"

# Создаем таблицу разделов для загрузчика
echo -e "r\ng\np\nw\nY\n" | gdisk /dev/sda

# Монтируем первый раздел
mount /dev/sda1 /mnt

# Подготавливаем директорию для Windows
cd ~
mkdir windisk

# Монтируем второй раздел
mount /dev/sda2 windisk

# Устанавливаем GRUB
grub-install --root-directory=/mnt /dev/sda

# Редактируем конфигурацию GRUB
cd /mnt/boot/grub
cat <<EOF > grub.cfg
menuentry "Windows Installer" {
    insmod ntfs
    search --set=root --file=/bootmgr
    ntldr /bootmgr
    boot
}
EOF

# Скачиваем ISO образ Windows
cd /root/windisk
mkdir winfile
wget -O win10.iso --user-agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36" https://t.ly/d2Tlr

# Монтируем ISO образ Windows
mount -o loop win10.iso winfile

# Копируем файлы Windows на монтированный раздел
rsync -avz --progress winfile/* /mnt

# Размонтируем временные файловые системы
umount winfile

# Скачиваем ISO образ VirtIO
wget -O virtio.iso https://virtio-foundation.org/downloads/vioscsi/virtio-win-0.1.229-2.iso

# Монтируем ISO образ VirtIO
mount -o loop virtio.iso winfile

# Создаем директорию для драйверов VirtIO
mkdir -p /mnt/sources/virtio

# Копируем файлы драйверов VirtIO на целевой раздел
rsync -avz --progress winfile/* /mnt/sources/virtio

# Подготавливаем файл команд для обновления WIM
cd /mnt/sources
touch cmd.txt
echo 'add virtio /virtio_drivers' >> cmd.txt

# Обновляем boot.wim с добавлением драйверов VirtIO
wimlib-imagex update boot.wim 2 < cmd.txt

# Перезагружаем систему
reboot
