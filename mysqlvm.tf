resource "azurerm_virtual_network" "vnet-vm" {
    name                = "vnet-vm"
    address_space       = ["10.0.0.0/16"]
    location            = "Brazil South"
    resource_group_name = azurerm_resource_group.RGAULATERRAFORM.name
}

resource "azurerm_subnet" "subnet-vm" {
    name                 = "subnet-vm"
    resource_group_name  = azurerm_resource_group.RGAULATERRAFORM.name
    virtual_network_name = azurerm_virtual_network.vnet-vm.name
    address_prefixes       = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "public-ip" {
    name                         = "public-ip"
    location                     = "Brazil South"
    resource_group_name          = azurerm_resource_group.RGAULATERRAFORM.name
    allocation_method            = "Static"
}

resource "azurerm_network_security_group" "nsg" {
    name                = "nsg"
    location            = "Brazil South"
    resource_group_name = azurerm_resource_group.RGAULATERRAFORM.name

    security_rule {
        name                       = "mysql"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "3306"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
        name                       = "SSH"
        priority                   = 1002
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }
}

resource "azurerm_network_interface" "nic" {
    name                      = "nic"
    location                  = "Brazil South"
    resource_group_name       = azurerm_resource_group.RGAULATERRAFORM.name

    ip_configuration {
        name                          = "ipconfiguration"
        subnet_id                     = azurerm_subnet.subnet-vm.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id          = azurerm_public_ip.public-ip.id
    }
}

resource "azurerm_network_interface_security_group_association" "nic-group" {
    network_interface_id      = azurerm_network_interface.nic.id
    network_security_group_id = azurerm_network_security_group.nsg.id
}

data "azurerm_public_ip" "ip_data_db" {
  name                = azurerm_public_ip.public-ip.name
  resource_group_name = azurerm_resource_group.RGAULATERRAFORM.name
}

resource "azurerm_storage_account" "storageaccountvmmysql" {
    name                        = "storageaccountvmmysql"
    resource_group_name         = azurerm_resource_group.RGAULATERRAFORM.name
    location                    = "Brazil South"
    account_tier                = "Standard"
    account_replication_type    = "LRS"
}

resource "azurerm_linux_virtual_machine" "vm" {
    name                  = "vm"
    location              = "Brazil South"
    resource_group_name   = azurerm_resource_group.RGAULATERRAFORM.name
    network_interface_ids = [azurerm_network_interface.nic.id]
    size                  = "Standard_DS1_v2"

    os_disk {
        name              = "OSdisk"
        caching           = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "Canonical"
        offer     = "UbuntuServer"
        sku       = "18.04-LTS"
        version   = "latest"
    }

    computer_name  = "mysqlvm"
    admin_username = var.user
    admin_password = var.password
    disable_password_authentication = false

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.storageaccountvmmysql.primary_blob_endpoint
    }

    depends_on = [ azurerm_resource_group.RGAULATERRAFORM ]
}

output "public_ip_address" {
  value = azurerm_public_ip.public-ip.ip_address
}

resource "time_sleep" "wait_30_seconds_db" {
  depends_on = [azurerm_linux_virtual_machine.vm]
  create_duration = "30s"
}

resource "null_resource" "upload_db" {
    provisioner "file" {
        connection {
            type = "ssh"
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.ip_data_db.ip_address
        }
        source = "mysql"
        destination = "/home/anderson"
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
            user = var.user
            password = var.password
            host = data.azurerm_public_ip.ip_data_db.ip_address
        }
        inline = [
            "sudo apt-get update",
            "sudo apt-get install -y mysql-server-5.7",
            "sudo mysql < /home/anderson/mysql/usercreate.sql",
            "sudo cp -f /home/anderson/mysql/mysqld.cnf /etc/mysql/mysql.conf.d/mysqld.cnf",
            "sudo service mysql restart",
            "sleep 20",
        ]
    }
}