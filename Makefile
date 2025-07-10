.PHONY: init update-deps

init:
	pip install -r requirements.txt
	ansible-galaxy install --force -r ansible-galaxy-reqs.yaml
	ansible-galaxy collection install --upgrade -r ansible-galaxy-collection-reqs.yaml
