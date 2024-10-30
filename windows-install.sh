#!/bin/bash

echo "*** Update and Upgrade ***"
apt update -y && apt upgrade -y
echo "Update and Upgrade finish ***"

echo "*** Install linux-image-amd64 ***"
sudo apt install linux-image-amd64 -y
echo "Install linux-image-amd64 finish ***"

echo "*** Reinstall initramfs-tools ***"
sudo apt install --reinstall initramfs-tools -y
echo "Reinstall initramfs-tools finish ***"

echo "*** Install grub2, wimtools, ntfs-3g ***"
apt install grub2 wimtools ntfs-3g -y
echo "Install grub2, wimtools, ntfs-3g finish ***"

echo "*** Get the disk size in GB and convert to MB ***"
disk_size_gb=$(parted /dev/sda --script print | awk '/^Disk \/dev\/sda:/ {print int($3)}')
disk_size_mb=$((disk_size_gb * 1024))
echo "Get the disk size in GB and convert to MB finish ***"

echo "*** Calculate partition size (50% of total size) ***"
part_size_mb=$((disk_size_mb / 2))
echo "Calculate partition size (50% of total size) finish ***"

echo "*** Create GPT partition table ***"
parted /dev/sda --script -- mklabel gpt
echo "Create GPT partition table finish ***"

echo "*** Create two partitions ***"
parted /dev/sda --script -- mkpart primary ntfs 1MB ${part_size_mb}MB
echo "Create first partition"
parted /dev/sda --script -- mkpart primary ntfs ${part_size_mb}MB 100%
echo "Create second partition"
echo "Create two partitions finish ***"

echo "*** Inform kernel of partition table changes ***"
partprobe /dev/sda
sleep 60

echo "*** Check if partitions are created and formatted successfully ***"
if lsblk /dev/sda1 && lsblk /dev/sda2; then
    echo "Partitions created successfully"
else
    echo "Error: Partitions were not created successfully"
    exit 1
fi

echo "*** Format the partitions ***"
mkfs.ntfs -f /dev/sda1
echo "Format partition sda1"
mkfs.ntfs -f /dev/sda2
echo "Format partition sda2"
echo "Format partitions finish ***"

echo "NTFS partitions created"

echo "*** Install gdisk ***"
sudo apt-get install gdisk -y
echo "Install gdisk finish ***"

echo "*** Run gdisk commands ***"
echo -e "r\ng\np\nw\nY\n" | gdisk /dev/sda
echo "Run gdisk commands finish ***"

echo "*** Mount /dev/sda1 to /mnt ***"
mount /dev/sda1 /mnt
echo "Mount /dev/sda1 to /mnt finish ***"

echo "*** Prepare directory for the Windows disk ***"
cd ~
mkdir -p windisk
echo "Prepare directory for the Windows disk finish ***"

echo "*** Mount /dev/sda2 to windisk ***"
mount /dev/sda2 windisk
echo "Mount /dev/sda2 to windisk finish ***"

echo "*** Install GRUB ***"
grub-install --root-directory=/mnt /dev/sda
echo "Install GRUB finish ***"

echo "*** Edit GRUB configuration ***"
cat <<EOF > /mnt/boot/grub/grub.cfg
menuentry "Windows Installer" {
    insmod ntfs
    search --no-floppy --set=root --file /bootmgr
    chainloader +1
    boot
}
EOF
echo "Edit GRUB configuration finish ***"

echo "*** Prepare winfile directory ***"
cd /root/windisk
mkdir -p winfile
echo "Prepare winfile directory finish ***"

# Download Windows ISO
read -p "Do you want to download Windows.iso? (Y/N): " download_choice

if [[ "$download_choice" == "Y" || "$download_choice" == "y" ]]; then
    read -p "Enter the URL for Windows.iso (leave blank to use default): " windows_url
    if [ -z "$windows_url" ]; then
        windows_url="https://bit.ly/3UGzNcB"  # Replace with actual default URL
    fi
    wget -O Windows.iso --user-agent="Mozilla/5.0" "$windows_url"
    echo "Download completed"
else
    echo "Please upload the Windows ISO to 'root/windisk' and name it 'Windows.iso'."
    read -p "Press any key to continue once uploaded..." -n1 -s
fi

echo "*** Check if Windows ISO exists ***"
if [ -f "Windows.iso" ]; then
    mount -o loop Windows.iso winfile
    rsync -avz --progress winfile/* /mnt
    umount winfile
    echo "Windows ISO processed successfully"
else
    echo "Windows.iso not found or failed to download"
    exit 1
fi

# Download Virtio ISO
read -p "Do you want to download the Virtio drivers ISO? (Y/N): " download_choice

if [[ "$download_choice" == "Y" || "$download_choice" == "y" ]]; then
    read -p "Enter the URL for Virtio.iso (leave blank to use default): " virtio_url
    if [ -z "$virtio_url" ]; then
        virtio_url="https://bit.ly/4d1g7Ht"  # Replace with actual default URL
    fi
    wget -O Virtio.iso --user-agent="Mozilla/5.0" "$virtio_url"
    echo "Download completed"
else
    echo "Please upload Virtio drivers ISO to 'root/windisk' and name it 'Virtio.iso'."
    read -p "Press any key to continue once uploaded..." -n1 -s
fi

echo "*** Check if Virtio ISO exists ***"
if [ -f "Virtio.iso" ]; then
    mount -o loop Virtio.iso winfile
    mkdir -p /mnt/sources/virtio
    rsync -avz --progress winfile/* /mnt/sources/virtio
    umount winfile
    echo "Virtio drivers processed successfully"
else
    echo "Virtio.iso not found or failed to download"
    exit 1
fi

cd /mnt/sources

touch cmd.txt
echo 'add virtio /virtio_drivers' >> cmd.txt

# Update boot.wim
echo "*** List images in boot.wim ***"
wimlib-imagex info boot.wim
echo "Enter a valid image index from the list above:"
read image_index

if [ -f boot.wim ]; then
    wimlib-imagex update boot.wim $image_index < cmd.txt
    echo "boot.wim updated successfully"
else
    echo "boot.wim not found"
    exit 1
fi

# Reboot prompt
read -p "Do you want to reboot the system now? (Y/N): " reboot_choice
if [[ "$reboot_choice" == "Y" || "$reboot_choice" == "y" ]]; then
    sudo reboot
else
    echo "Continuing without rebooting"
fi
