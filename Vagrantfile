# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

    # We use the bento namespace for Ubuntu boxes as the ubuntu one is broken.
    # See https://github.com/hashicorp/vagrant/issues/7155#issuecomment-228568200

    # Use Ubuntu Trusty, 14.04 LTS (PHP5)
    #config.vm.box = "bento/ubuntu-14.04"

    # Use Ubuntu Xenial, 16.04 LTS (PHP7)
    config.vm.box = "bento/ubuntu-16.04"

    config.vm.network "private_network", ip: "192.168.33.11"
    config.vm.synced_folder ".", "/var/www", :mount_options => ["dmode=777", "fmode=777"]

    # Optional NFS. Make sure to remove other synced_folder line too
    #config.vm.synced_folder ".", "/var/www", :nfs => { :mount_options => ["dmode=777","fmode=666"] }

    config.ssh.insert_key = false
    config.ssh.private_key_path = ["~/.ssh/id_rsa", "~/.vagrant.d/insecure_private_key"]
    config.vm.provision "file", source: "~/.ssh/id_rsa.pub", destination: "~/.ssh/authorized_keys"

    # Define the bootstrap file: A (shell) script that runs after first setup of your box (= provisioning)
    # Provision using Ansible
    config.vm.provision "ansible" do |ansible|
      ansible.playbook = "ansible/playbook.yml"
    end

    # Provision static IP manually
    #config.vm.provision "shell", run: "always", inline: "ifconfig enp0s8 192.168.33.11 netmask 255.255.255.0 up"

end
