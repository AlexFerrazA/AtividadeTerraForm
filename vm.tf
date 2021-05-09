terraform {
  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      version = ">= 2.26"
    }
  }

  required_version = ">= 0.13"
}

provider "azurerm" {
  skip_provider_registration = true
  features {}
}

resource "azurerm_resource_group" "terrafromgroup" {
  name     = "myTFResourceGroup"
  location = "eastus"
   tags = {
    "Environment" = "Atividade Terraform"
  }
}

resource "azurerm_virtual_network" "terraformnetwork" {
    name                = "myVnet"
    address_space       = ["10.0.0.0/16"]
    location            = "eastus"
    resource_group_name = azurerm_resource_group.terrafromgroup.name
}

resource "azurerm_subnet" "terraformsubnet" {
    name                 = "mySubnet"
    resource_group_name  = azurerm_resource_group.terrafromgroup.name
    virtual_network_name = azurerm_virtual_network.terraformnetwork.name
    address_prefixes       = ["10.0.1.0/24"]
}


resource "azurerm_public_ip" "terraformpublicip" {
    name                         = "PublicIP"
    location                     = "eastus"
    resource_group_name          = azurerm_resource_group.terrafromgroup.name
    allocation_method            = "Static"
}



resource "azurerm_network_security_group" "terraformnsg" {
    name                = "MeuSQL"
    location            = "eastus"
    resource_group_name = azurerm_resource_group.terrafromgroup.name

    security_rule {
        name                       = "SSH"
        priority                   = 1000
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }


    security_rule {
        name                       = "SQL"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

}

resource "azurerm_network_interface" "terraformnic" {
    name                      = "NIC"
    location                  = "eastus"
    resource_group_name       = azurerm_resource_group.terrafromgroup.name

    ip_configuration {
        name                          = "NicConfiguration"
        subnet_id                     = azurerm_subnet.terraformsubnet.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.terraformpublicip.id
    }
}

resource "azurerm_network_interface_security_group_association" "example" {
    network_interface_id      = azurerm_network_interface.terraformnic.id
    network_security_group_id = azurerm_network_security_group.terraformnsg.id
}


resource "azurerm_storage_account" "mystorageaccount" {
    name                        = "storageaccountmyvm"
    resource_group_name         = azurerm_resource_group.terrafromgroup.name
    location                    = "eastus"
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}


resource "azurerm_linux_virtual_machine" "myterraformvm" {
    name                  = "myVM"
    location              = "eastus"
    resource_group_name   = azurerm_resource_group.terrafromgroup.name
    network_interface_ids = [azurerm_network_interface.terraformnic.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "myOsDisk"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "myvm"
    admin_username = "alexandre"
    admin_password = "senhamaior1992@"
    disable_password_authentication = false


    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.mystorageaccount.primary_blob_endpoint
    }

    depends_on = [ azurerm_resource_group.terrafromgroup ]
}







resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.myterraformvm]
  create_duration = "30s"
}

resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = "alexandre"
            password = "senhamaior1992@"
            host = azurerm_public_ip.terraformpublicip.ip_address
        }
        source = "config"
        destination = "/home/alexandre"
    }

    depends_on = [ time_sleep.wait_30_seconds_db ]
}

resource "null_resource" "deploy_db" {
    triggers = {
        order = null_resource.upload_db.id
    }
    provisioner "remote-exec" {
        connection {
            type = "ssh"
            user = "alexandre"
            password = "senhamaior1992@"
            host = azurerm_public_ip.terraformpublicip.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/alexandre/config/user.sql",
            "sudo cp -f /home/alexandre/config/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}

output "public_ip_address" {
  value = azurerm_public_ip.terraformpublicip.ip_address
}
