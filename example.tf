provider "aws" {
  profile    = "default"
  region     = "us-west-2"
}

resource "aws_instance" "example" {
  ami           = "ami-bff64fdf"
  instance_type = "t2.micro"
}
