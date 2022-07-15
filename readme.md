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
## Debug CGI web files
Because Cisco webSevices is handled by `nginx`, it receives json data and sends to `cgi` files, so it's difficult to debug webServices directly. Luckily Cisco's device includes `python2`, so I can write a simple python script to handle web requests:
```python
#!/usr/bin/python

from subprocess import Popen, PIPE, STDOUT, check_output
import base64

#passwd_enc = base64.b64encode(b"A"*150)
passwd_enc = b"\x01"*200

# you can fill your json data request here
request = b"{\"jsonrpc\":\"2.0\",\"method\":\"login\",\"params\":{\"user\":\"sssss\",\"pass\":\"" + passwd_enc + "\",\"lang\":\"English\"}}"

print (request)
print ("[+] content length: %d" %len(request))
p = Popen(['/tmp/gdbserver', ':9999', '/www/cgi-bin/jsonrpc.cgi'], stdin=PIPE, stdout=PIPE)
p.stdin.write(request)
out, err = p.communicate()
print (out)

```
My script works when I debug `blockpage.cgi` file, I hope this can help you!

