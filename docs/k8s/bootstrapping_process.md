# Manual steps during the bootstrap phase we must work out or be aware of:

### To configure proper DNS resolution for the runner host:

`sudo nano /opt/docker/gitlab-runner/config/config.toml`

within the file after the `[runners.docker]` section

add a line: `dns = ["10.0.0.1","10.0.0.2","1.1.1.1","8.8.8.8"]`

Simply editing this file as such should resolve DNS resolution for the next push.

### Also we will need to add the public keys to the authorized key list for each host:

`sudo nano ~/.ssh/authorized_keys` and then paste the key into a newline.

### Need to enable sudo without a password on each of the hosts:

sudo visudo

$USER ALL=(ALL) NOPASSWD: ALL


Debian Host Pre-Ansible adoption Preparation
###  run as root
```
apt install sudo
usermod -aG sudo kai
sudo -u kai ssh-keygen -b 4096
sudo -u kai sudo nano ~/.ssh/authorized_keys
# add the public key
```

app passwords should be by the security domain actually and obviously
so name them by the vlan id tag and then divide them from there. So trust is placed in the distribution of isolation only and sometimes maybe to filter specific resources! That is how service accounts should be handled to minimize having excessive accounts.
