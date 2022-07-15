# Simulate RV34X Cisco

Example with Cisco fimware version 22 and 26 (there are 2 versions newest when I simulated the device)

### Step 0: Install qemu-system
Because I used qemu-vm as enviroment for `arm` architecture
```
sudo apt-get install qemu-system
```

### Step 1: Run `simulate.sh` file to download ARM 32bits images for QEMU and starts it
```
./simulate.sh
```
account login:
- username: root
- password: root

### Step 2: Copy Cisco ubiroot filesystems from your machine to qemu sandbox
```
# version 26
scp -P 2222 fw_26.tar root@localhost:/root

# version 22
scp -P 2222 fw_22.tar root@localhost:/root

scp -P 2222 start.sh root@localhost:/root
```
### Step 3: Start Cisco services
I'm not sure for all services can run, but I'm done with webservice simulation.
In qemu vm, you run command to simulate fimware version 26:
```
./start.sh 26
```
