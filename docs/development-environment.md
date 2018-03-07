# Development environment

You need [Vagrant](https://www.vagrantup.com/), [VirtualBox](https://www.virtualbox.org/)
and [Ansible](https://www.ansible.com/) installed to setup the development environment.
If you are on a Linux system you must use Vagrant `> 1.8.1`.

In the project root folder, run:

```
vagrant up
```

This will download a Vagrant box based on Ubuntu Xenial and provision it using
the `ansible/playbook.yml` file.

Before turn your computer off you should suspend the VM by running:

```
vagrant suspend
```

## Add a custom host name

Edit your local `/etc/hosts` file and add:

```
192.168.33.11   hostname.dev www.hostname.dev
```

## Connect using SSH

Just run  `vagrant ssh` from the project root folder.


### Connect to remote server from within the guest VM

If you like to be able to connect to remote servers from within the guest VM
you have to enable _SSH agent forwarding_ on your host machine.

Edit your local `~/.ssh/config` file and add the following:

```
Host *
  ForwardAgent      yes
```

Then make sure your your SSH agent is aware of your key, run `ssh-add -l`. If
your key is listed there you are ready to go. If not make the SSH agent aware
by running `ssh-add ~/.ssh/id_rsa`.


## Connect to the database from host machine

If you want to inspect the database using a desktop application installed on
the host machine you can do that via SSH. Use the following information when
creating the connection:

```
SSH host: 192.168.33.11
SSH user: vagrant
SSH password: -
SSH key: Your private key
SSH Port: 22

MySQL host: 127.0.0.1
MySQL user: root
MySQL password: root
MySQL port: 3306
```

## Debug with Xdebug

In order to enable remote debug using Xdebug PHPStorm needs to be configured.
We need to setup a _Deployment_ and a _Remote interpreter_.

### Adding a deployment

1. Click _Tools > Deployment > Configuration ..._
2. Click the small `+`-button on the top left side of the window
3. Enter a name for the deployment and select **SFTP**
4. Enter values for host:
    * SFTP host: `www.project.dev`
    * Port: `22`
    * Root path: `/`
5. Enter values for connection to the Vagrant instance:
   * User name: `vagrant`
   * Auth type: `Keypair (OpenSSH or PuTTY)`
   * Private key file: `/Users/name/.ssh/id_rsa`
6. Click the _Mappings_ tab and fill in the information:
   * Local path: `/Users/name/Sites/project/web`
   * Deployment path on server 'Server name': `/var/www/web`
   * Web path on server 'Server name': `/`
7. Click **OK**

## Setup remote interpreter

1. In the menu, click _PhpStorm > Preferences_
2. Navigation to _Languages & Frameworks > PHP_
3. Click the `...`-button next to _CLI Interpreter_
4. Click the small `+`-button on the top left side of the window
5. Select the option _From Docker, Vagrant, VM, Remote..._
6. Tick the box _Deployment configuration_ and select the deployment you
created earlier
7. Click **OK**

## Test your configuration

To make sure Xdebug is connecting to PhpStorm set a breakpoint, for example
in the `index.php` file, and enable debug by clicking _Start listening for
PHP Debug Connections_. Load the project in your browser a check if debug
data is displayed in PhpStorm.

## Protect development site

Enable Basic authentication for sites in development phase by using the
included `/.htpasswd` file with the following credentials:

* Username: beta
* Password: beta
