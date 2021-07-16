init:
	conda init bash
	conda init zsh
	conda create -y --prefix ./.venv python=3.8
	conda activate ./.venv
	pip install -r requirements.txt

freeze:
	pip freeze > requirements-freeze.txt

update:
	pip install --upgrade --force-reinstall -r requirements.txt

build:
	cd gui; npm run build-prod

run:
	python main.py

prod: build run

package: build
	rm -rf terminal.tar.gz
	mkdir package/
	cp -R gui/dist package/gui
	cp -R tradingterminal package/tradingterminal
	cp -R config/pi.yaml package/config.yaml
	cp -R main.py package/main.py
	cp -R startup.sh package/startup.sh
	cp -R requirements-freeze.txt package/requirements-freeze.txt
	tar -zcvf terminal.tar.gz package
	rm -rf package
