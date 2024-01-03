# Rust for Linux

## Setup Ubuntu

### Network
Set network `Bridge` on UTM

### Share folder
```sh
sudo mkdir [mount point]
sudo mount -t 9p -o trans=virtio share [mount point] -oversion=9p2000.L
# fix permission
sudo chown -R $USER [mount point]
```
### Download Rust-for-Linux
```sh
git clone -b rust https://github.com/Rust-for-Linux/linux.git --depth=1
```

## Dependencies

### System Requirements
```sh
sudo apt install clang
sudo apt install libncurses-dev flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf
```

### QEMU & GDB
```sh
sudo apt install qemu qemu-system qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
sudo apt install gdb
```
### LLVM (or libclang)
```sh
sudo apt install llvm lld libclang-dev
```

### Install Rust
```sh
# check rust support environment
make LLVM=1 rustavailable
# install rustup
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
# set version
rustup override set $(scripts/min-tool-version.sh rustc)
# Rust standard library source
rustup component add rust-src rustfmt clippy rust-analyzer
# Install bindgen
cargo install --locked --version $(scripts/min-tool-version.sh bindgen) bindgen-cli
```

### Enable kernel support
Create `rust-qemu-busybox-min.config` file and move to `kernel/configs` folder.
<details>
  <summary>kernel/configs/rust-qemu-busybox-min.config</summary>

```conf
# This is a minimal configuration for running a busybox initramfs image with
# networking support.
#
# The following command can be used create the configuration for a minimal
# kernel image:
#
# make allnoconfig qemu-busybox-min.config
#
# The following command can be used to build the configuration for a default
# kernel image:
#
# make defconfig qemu-busybox-min.config
#
# On x86, the following command can be used to run qemu:
#
# qemu-system-x86_64 -nographic -kernel vmlinux -initrd initrd.img -nic user,model=rtl8139,hostfwd=tcp::5555-:23
#
# On arm64, the following command can be used to run qemu:
#
# qemu-system-aarch64 -M virt -cpu cortex-a72 -nographic -kernel arch/arm64/boot/Image -initrd initrd.img -nic user,model=rtl8139,hostfwd=tcp::5555-:23

# Enable 64-bit for support Rust
CONFIG_64BIT=y
CONFIG_RUST=y

# Support vmlinux
CONFIG_HYPERVISOR_GUEST=y
CONFIG_PVH=y

# Enable to mount external kernel module
CONFIG_MODULES=y
CONFIG_MODULE_FORCE_LOAD=y
CONFIG_MODULE_UNLOAD=y
CONFIG_MODULE_FORCE_UNLOAD=y
CONFIG_MODULE_UNLOAD_TAINT_TRACKING=y

# Enable Rust samples
CONFIG_SAMPLES=y
CONFIG_SAMPLES_RUST=y
CONFIG_SAMPLE_RUST_MINIMAL=y
CONFIG_SAMPLE_RUST_PRINT=y
CONFIG_SAMPLE_RUST_HOSTPROGS=y

CONFIG_SMP=y
CONFIG_PRINTK=y
CONFIG_PRINTK_TIME=y

CONFIG_PCI=y

# We use an initramfs for busybox with elf binaries in it.
CONFIG_BLK_DEV_INITRD=y
CONFIG_RD_GZIP=y
CONFIG_BINFMT_ELF=y
CONFIG_BINFMT_SCRIPT=y

# This is for /dev file system.
CONFIG_DEVTMPFS=y

# Core networking (packet is for dhcp).
CONFIG_NET=y
CONFIG_PACKET=y
CONFIG_INET=y

# RTL8139 NIC support.
CONFIG_NETDEVICES=y
CONFIG_ETHERNET=y
CONFIG_NET_VENDOR_REALTEK=y
CONFIG_8139CP=y

# To get GDB symbols and script.
CONFIG_DEBUG_KERNEL=y
CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT=y
CONFIG_GDB_SCRIPTS=y

# For the power-down button (triggered by qemu's `system_powerdown` command).
CONFIG_INPUT=y
CONFIG_INPUT_EVDEV=y
CONFIG_INPUT_KEYBOARD=y
```
</details>

then merge configs and see result.
```sh
make LLVM=1 allnoconfig rust-qemu-busybox-min.config  
make LLVM=1 menuconfig   # optional for checking which function is open

### Build kernel
```sh
time make LLVM=1 -j$(nproc)
```

## Build busybox
```sh
git clone https://github.com/mirror/busybox.git --depth=1
```
### Building config
```sh
make menuconfig
```
enable `Settings -> Build static binary (no shared libs)` then compile
```sh
time make -j$(nproc)
```

Install the binaries to `./_install` directory:
```sh
make install
```

### Configuring the rootfs
Now, in the ./_install directory, we need to create the following directories:
```sh
cd _install
mkdir -p usr/share/udhcpc/ etc/init.d/
```
With those dirs created, we can create the etc/init.d/rcS init script:
```sh
cat <<EOF > etc/init.d/rcS
mkdir -p /proc
mount -t proc none /proc
ifconfig lo up
ifconfig eth0 up
udhcpc -i eth0
mount -t devtmpfs none /dev
mkdir -p /dev/pts
mount -t devpts nodev  /dev/pts
telnetd -l /bin/sh
EOF
chmod a+x etc/init.d/rcS bin/*
```
Copy the `examples/inittab` file to the `etc`:
```sh
cp ../examples/inittab etc/
```
Copy the `examples/udhcpc/simple.script` file to the `usr/share/udhcpc/default.script`:
```sh
cp ../examples/udhcp/simple.script usr/share/udhcpc/default.script
```
### Creating the rootfs
Now, we can create a cpio image with the rootfs:
```sh
find . | cpio -o -H newc | gzip -9 > ./rootfs.img
```
## Wrapping all up in a Virtual Machine using QEMU
```sh
cd ../..
qemu-system-x86_64 \
    -kernel linux/vmlinux \
    -initrd busybox/_install/rootfs.img \
    -nographic \
    -nic user,model=rtl8139,hostfwd=tcp::5555-:23,hostfwd=tcp::5556-:8080 
    # -virtfs local,path=</host/path/to/share>,mount_tag=hostshare,security_model=none,id=hostshare
```

then can connect from the host to the virtual machine using telnet:
```sh
telnet localhost 5555
```

test `rust_echo_server` module:
> The code on the branch `rust` of repo `Rust-for-Linux`
```sh
# telnet localhost 8080 (from the guest)
telnet localhost 5556
```

## IDE Support
`rust-analyzer` needs a configuration file, `rust-project.json`, which can be generated by the rust-analyzer Make target:
> Need to run `make LLVM=1 allnoconfig qemu-busybox-min.config rust.config`
```sh
make LLVM=1 rust-analyzer
```
## rust-out-of-tree-module
```sh
git clone https://github.com/Rust-for-Linux/rust-out-of-tree-module.git
```
compile
```sh
make LLVM=1 KDIR=.../linux-with-rust-support 
```

## GDB debug
``` bash
qemu-system-x86_64 \
    -kernel vmlinux \
    -initrd rootfs.img \
    -nographic \
    -s -S
```
```bash
gdb vmlinux
```
如果gdb报告拒绝加载vmlinux-gdb.py（相关命令找不到），请将:
```bash
add-auto-load-safe-path /path/to/linux-build
```
添加到~/.gdbinit

## Clean 
```sh
make clean
# or 
make mrproper
```

## Issue

### Permission
```sh
chmod +x scripts/**/*
chmod +x tools/**/*
chmod +x init/**/*
chmod +x arch/x86/tools/**/*
```

# Reference
- https://gist.github.com/m13253/e4c3e3a56a23623d2e7e6796678b9e58
- https://gist.github.com/chrisdone/02e165a0004be33734ac2334f215380e
- https://tomcat0x42.me/linux/rust/2023/04/01/linux-kernel-rust-dev-environment.html
- https://docs.kernel.org/next/rust/quick-start.html
- https://wusyong.github.io/posts/rust-kernel-module-00/
- https://rustmagazine.org/issue-1/rust-for-linux-brief-introduction/
- https://mp.weixin.qq.com/s/I1o-pijdrJDzKF6JisdZMA
- https://mp.weixin.qq.com/s/bvXblBFUIc1OAe6fkNgwXQ
