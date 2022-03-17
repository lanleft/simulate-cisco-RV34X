# Simulate RV34X Cisco

Example with Cisco fimware version ...26

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
scp -P 2222 fw_26.tar root@localhost:/root
scp -P 2222 start.sh root@localhost:/root
```
### Step 3: Start service cisco
In qemu vm, you run command:
```
./start.sh
```