# luks_mount
Decrypt LUKS disks and mount them on boot


## How script works

1. Script checks if any of the attached volumes is a LUKS device
2. If it is, then it requests `LUKS_KEY` to [vault](https://www.vaultproject.io/) using path `secret/${HOSTNAME}/luks_${DEV}`
3. LUKS device is opened and mounted according to `/etc/fstab`


## Assumptions

- Client machines are running `Ubuntu 16.04`
- Client has package `python-apt` (needed for ansible)
- `VAULT_TOKEN` has permission to read path `secret/${HOSTNAME}/luks_${DEV}` on VAULT_SERVER
- LUKS disks have been `luksFormat`
- LUKS disks have a file system
- Mounting point for LUKS volumes are listed on `/etc/fstab` and follow convention:

  ```
  /dev/mapper/luks_DEVICE  /mount_point  fstype   noauto    0  0
  ```
- Services that depend on information on the encrypted disks will have `After=luks_mount.service` 
  on their systemd service files

## Deployment

1. Change `VAULT_ADDR` and `VAULT_TOKEN` on `luks_mount.conf`
2. Run ansible playbook:

```
ansible-playbook \
   -i "SERVER1,SERVER2" \
   --ssh-extra-args "-i SSHKEY.pem" \
   -u USER \
   deploy_luks_mount.yml
```


## Example

ansible deployment

```
$ ansible-playbook -i "1.2.3.4," --ssh-extra-args "-i mykey.pem" -u ubuntu  deploy_luks_mount.yml

PLAY [all] *********************************************************************

TASK [setup] *******************************************************************
ok: [1.2.3.4]

TASK [Check required packages are installed] ***********************************
changed: [1.2.3.4] => (item=[u'cryptsetup', u'jq'])

TASK [Upload script to remote server] ******************************************
changed: [1.2.3.4]

TASK [Upload script config file to remote server] ******************************
changed: [1.2.3.4]

TASK [Upload systemd init script] **********************************************
changed: [1.2.3.4]

TASK [Enable new systemd service] **********************************************
changed: [1.2.3.4]

PLAY RECAP *********************************************************************
1.2.3.4               : ok=6    changed=5    unreachable=0    failed=0
```

Script in action soon after a reboot

```
root@client2:~# uptime
 21:16:26 up 1 min,  1 user,  load average: 0.28, 0.12, 0.04


root@client2:~# lsblk
NAME        MAJ:MIN  RM SIZE RO TYPE  MOUNTPOINT
xvda        202:0     0   8G  0 disk
└─xvda1     202:1     0   8G  0 part  /
xvdy        202:6144  0  10G  0 disk
└─luks_xvdy 252:0     0  10G  0 crypt /encrypted1
xvdz        202:6400  0  11G  0 disk
└─luks_xvdz 252:1     0  11G  0 crypt /encrypted2


root@client2:~# cat /etc/fstab
LABEL=cloudimg-rootfs  /            ext4  defaults,discard  0  0
/dev/mapper/luks_xvdy  /encrypted1  xfs   noauto            0  0
/dev/mapper/luks_xvdz  /encrypted2  xfs   noauto            0  0


root@client2:~# systemctl status luks_mount.service
● luks_mount.service - Decrypt LUKS disks and mount them on boot
   Loaded: loaded (/etc/systemd/system/luks_mount.service; enabled; vendor preset: enabled)
   Active: active (exited) since Tue 2017-02-14 21:15:33 UTC; 34s ago
  Process: 1141 ExecStart=/usr/sbin/luks_mount.sh (code=exited, status=0/SUCCESS)
 Main PID: 1141 (code=exited, status=0/SUCCESS)
    Tasks: 0
   Memory: 0B
      CPU: 0
   CGroup: /system.slice/luks_mount.service

Feb 14 21:15:29 client2 luks_mount.sh[1141]: Luks devices are:  xvdy xvdz
Feb 14 21:15:29 client2 luks_mount.sh[1141]: Succesfully retrieved keys for xvdy
Feb 14 21:15:31 client2 luks_mount.sh[1141]: Key slot 0 unlocked.
Feb 14 21:15:31 client2 luks_mount.sh[1141]: Command successful.
Feb 14 21:15:31 client2 luks_mount.sh[1141]: Succesfully decrypted volume xvdy
Feb 14 21:15:31 client2 luks_mount.sh[1141]: Succesfully retrieved keys for xvdz
Feb 14 21:15:33 client2 luks_mount.sh[1141]: Key slot 0 unlocked.
Feb 14 21:15:33 client2 luks_mount.sh[1141]: Command successful.
Feb 14 21:15:33 client2 luks_mount.sh[1141]: Succesfully decrypted volume xvdz
Feb 14 21:15:33 client2 systemd[1]: Started Decrypt LUKS disks and mount them on boot.


root@client2:~# grep PRETTY_NAME /etc/os-release
PRETTY_NAME="Ubuntu 16.04.1 LTS"
```

## LIMITATIONS

One of the main limitations of this solution is that the vault token is never rotated.
It's also available locally on `/etc/luks_mount.conf` (although file is protected with `0400`)

A possible solution could be a workflow as follows:

1. Orchestrator machine generates a one time VAULT token with permission 
   to view `secret/${HOSTNAME}/luks_${DEV}`
2. Orchestrator machine starts client VM and injects one-time TOKEN inside 
   [instance metadata](https://cloud.google.com/compute/docs/storing-retrieving-metadata)
3. Client boots up, retrieves one-time TOKEN from metadata and uses it to decrypt LUKS volumes
4. one-time TOKEN is automatically revoked by VAULT server