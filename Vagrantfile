# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|

    # We use the bento namespace for Ubuntu boxes as the ubuntu one is broken.
    # See https://github.com/hashicorp/vagrant/issues/7155#issuecomment-228568200

    # Use Ubuntu Xenial, 16.04 LTS (PHP7)
    config.vm.box = "bento/ubuntu-18.04"

    config.vm.network "private_network", ip: "192.168.33.11"

    config.ssh.insert_key = false
    config.ssh.private_key_path = ["~/.ssh/id_rsa", "~/.vagrant.d/insecure_private_key"]
    config.vm.provision "file", source: "~/.ssh/id_rsa.pub", destination: "~/.ssh/authorized_keys"

    # Define the bootstrap file: A (shell) script that runs after first setup of your box (= provisioning)
    # Provision using Ansible
    config.vm.provision "ansible" do |ansible|
      ansible.playbook = "ansible/playbook.yml"
    end

    # Allow an untracked Vagrantfile to modify the configurations
    project_dir = File.dirname(File.expand_path(__FILE__))
    [project_dir].uniq.each do |dir|
        eval File.read "#{dir}/Vagrantfile.local" if File.exist?("#{dir}/Vagrantfile.local")
    end

end
