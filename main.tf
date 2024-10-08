# Configuración del proveedor AWS
provider "aws" {
  region = "us-west-2"  # Cambia esto a tu región preferida
}

# VPC
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  
  tags = {
    Name = "reverse-proxy-vpc"
  }
}

# Subred pública
resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  
  tags = {
    Name = "reverse-proxy-public-subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "reverse-proxy-igw"
  }
}

# Tabla de rutas
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "reverse-proxy-public-rt"
  }
}

# Asociación de la tabla de rutas con la subred
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Grupo de seguridad
resource "aws_security_group" "reverse_proxy" {
  name        = "reverse-proxy-sg"
  description = "Security group for reverse proxy"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP_ADDRESS/32"]  # Reemplaza con tu IP para acceso SSH
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "reverse-proxy-sg"
  }
}

# EC2 Instance
resource "aws_instance" "reverse_proxy" {
  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2 AMI (cambia según tu región)
  instance_type = "t2.micro"
  key_name      = "your-key-pair"  # Reemplaza con tu par de claves

  vpc_security_group_ids = [aws_security_group.reverse_proxy.id]
  subnet_id              = aws_subnet.public.id

  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y nginx
              systemctl start nginx
              systemctl enable nginx
              
              # Configuración básica de Nginx como reverse proxy
              cat > /etc/nginx/nginx.conf <<EOL
              user nginx;
              worker_processes auto;
              error_log /var/log/nginx/error.log;
              pid /run/nginx.pid;

              events {
                  worker_connections 1024;
              }

              http {
                  log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                                    '\$status \$body_bytes_sent "\$http_referer" '
                                    '"\$http_user_agent" "\$http_x_forwarded_for"';

                  access_log  /var/log/nginx/access.log  main;

                  sendfile            on;
                  tcp_nopush          on;
                  tcp_nodelay         on;
                  keepalive_timeout   65;
                  types_hash_max_size 2048;

                  include             /etc/nginx/mime.types;
                  default_type        application/octet-stream;

                  server {
                      listen       80 default_server;
                      listen       [::]:80 default_server;
                      server_name  _;
                      root         /usr/share/nginx/html;

                      location / {
                          proxy_pass http://backend_server;  # Reemplaza con la dirección de tu backend
                          proxy_set_header Host \$host;
                          proxy_set_header X-Real-IP \$remote_addr;
                      }
                  }
              }
              EOL

              systemctl restart nginx
              EOF

  tags = {
    Name = "reverse-proxy-vm"
  }
}

# Elastic IP
resource "aws_eip" "reverse_proxy" {
  instance = aws_instance.reverse_proxy.id
  vpc      = true

  tags = {
    Name = "reverse-proxy-eip"
  }
}

# Output
output "public_ip" {
  description = "Public IP of the reverse proxy"
  value       = aws_eip.reverse_proxy.public_ip
}