## 景嘉微mwv206显卡Linux内核驱动

### 来源

从 http://www.jingjiamicro.com/download/40/1.html 下载。

### 编译安装

### 为当前内核编译

```
sudo apt install git
git clone https://gitee.com/SwimmingTiger/mwv206.git
cd mwv206
sudo make -j$(nproc)
sudo make install
sudo update-initramfs -u
```

### 为指定版本的内核编译

```
KERNELVER=5.4.18
sudo apt install git
git clone https://gitee.com/SwimmingTiger/mwv206.git
cd mwv206
sudo make -j$(nproc) KERNELVER=$KERNELVER
sudo make install
sudo update-initramfs -u -k $KERNELVER
```
