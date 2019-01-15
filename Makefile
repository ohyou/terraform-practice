destroy:
	terraform destroy -auto-approve
apply:
	terraform apply -auto-approve
rebuild:
	terraform destroy -auto-approve && terraform apply -auto-approve