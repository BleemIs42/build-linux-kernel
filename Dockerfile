FROM ubuntu:latest

RUN apt update && \
    apt install -y git curl qemu qemu-system gdb libncurses-dev gawk flex bison openssl libssl-dev dkms libelf-dev libudev-dev libpci-dev libiberty-dev autoconf llvm clang lld libclang-dev cpio bc

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y

ENV PATH="/root/.cargo/bin:${PATH}"

RUN git clone https://github.com/mirror/busybox.git --depth=1

RUN git clone https://github.com/Rust-for-Linux/rust-out-of-tree-module.git

RUN git clone https://github.com/Rust-for-Linux/linux.git --depth=1

WORKDIR /linux

RUN rustup override set $(scripts/min-tool-version.sh rustc) && \
    rustup component add rust-src rustfmt clippy rust-analyzer && \
    cargo install --locked --version $(scripts/min-tool-version.sh bindgen) bindgen-cli

CMD ["bash"]
