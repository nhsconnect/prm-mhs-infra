
resource "aws_key_pair" "mhs-key" {
  key_name   = "mhs-${var.environment}-ssh-key"
  public_key = file("${path.module}/ssh/id_rsa.pub")
}
