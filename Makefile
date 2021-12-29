env:
	conda init bash
	conda init zsh
	conda create -y --prefix ./.venv python=3.8
	conda activate ./.venv
	pip install -r requirements.txt

freeze:
	pip freeze > requirements-freeze.txt

update:
	pip install --upgrade --force-reinstall -r requirements.txt

run:
	python main.py
