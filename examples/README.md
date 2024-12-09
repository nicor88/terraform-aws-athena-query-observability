## Getting started

Initialize the example variables containing the buckets to use
```
cp example.tfvars.example dev.tfvars
```

Initialize the terraform project:
```
terraform init
```

Run a terraform plan to see the changes that will be applied:
```
terraform plan -var-file "dev.tfvars"
```

Run a terraform apply to apply the changes:
```
terraform apply -var-file "dev.tfvars"
```

Finally, you can destroy the terraform resources used for testing running:

```
terraform destroy -var-file "dev.tfvars"
```
