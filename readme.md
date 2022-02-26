# Simulate RV34X Cisco


### Step 0: Install qemu-system
```
sudo apt-get install qemu-system
```

### Step 1: Run file simulate to download ARM 32bits image for qemu and start it
```
./simulate.sh
```
account login:
- username: root
- password: root

### Step 2: Copy ubiroot file system of Cisco to qemu sandbox
```
scp -P 2222 fw_22.tar root@localhost:/root

chmod -R 777 ubifs-root
```

### Step 3: Start service cisco
```
/etc/init.d/boot boot
generate_default_cert
/etc/init.d/confd start
/etc/init.d/nginx start
```