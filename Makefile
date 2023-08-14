env:
	conda init bash
	conda init zsh
	conda create -n PyMetaTrader python=3.11
	conda activate PyMetaTrader
	pip install -r requirements.txt

freeze:
	pip freeze > requirements-freeze.txt

update:
	pip install --upgrade --force-reinstall -r requirements.txt

run:
	python main.py
